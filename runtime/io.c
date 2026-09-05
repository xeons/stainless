/*
 * Stainless - an experimental systems language.
 * Copyright (C) 2026 Brandon Scott
 *
 * This file is part of the Stainless runtime library. It is free
 * software: you can redistribute it and/or modify it under the terms of
 * the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any
 * later version.
 *
 * It is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * As an additional permission under section 7 of that License, compiling
 * a program with Stainless does not by itself place that program under
 * the GNU General Public License. See LICENSE.RUNTIME.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

/*
 * Files and directories.
 *
 * Paths arrive as UTF-8, which is what a Stainless String already is. On
 * Windows that has to become UTF-16 before it reaches the operating system:
 * the narrow CRT entry points interpret bytes in the active code page, so
 * fopen on a UTF-8 path works by accident for ASCII and fails for everything
 * else. Every path here therefore goes through sl_widen() first, and the wide
 * entry points are used throughout.
 *
 * Errors come back as a small stable enum rather than errno, because errno's
 * values are not the same on two platforms and a Stainless enum is a value
 * that crosses the boundary as itself.
 */

#include "stainless.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  include <direct.h>
#  include <io.h>
#else
#  include <dirent.h>
#  include <unistd.h>
#endif

/* ------------------------------------------------------------ error codes */

/* Must match Standard.IO.IOError. */
enum {
    SL_IO_OK = 0,
    SL_IO_NOT_FOUND = 1,
    SL_IO_ACCESS_DENIED = 2,
    SL_IO_ALREADY_EXISTS = 3,
    SL_IO_NOT_A_DIRECTORY = 4,
    SL_IO_IS_A_DIRECTORY = 5,
    SL_IO_INVALID = 6,
    SL_IO_END_OF_FILE = 7,
    SL_IO_CLOSED = 8,
    SL_IO_UNKNOWN = 9
};

static int32_t from_errno(int code)
{
    switch (code) {
    case 0:       return SL_IO_OK;
    case ENOENT:  return SL_IO_NOT_FOUND;
    case EACCES:  return SL_IO_ACCESS_DENIED;
    case EPERM:   return SL_IO_ACCESS_DENIED;
    case EEXIST:  return SL_IO_ALREADY_EXISTS;
    case ENOTDIR: return SL_IO_NOT_A_DIRECTORY;
    case EISDIR:  return SL_IO_IS_A_DIRECTORY;
    case EINVAL:  return SL_IO_INVALID;
    case ENOSPC:  return SL_IO_UNKNOWN;
    default:      return SL_IO_UNKNOWN;
    }
}

static void report(int32_t *error, int32_t value)
{
    if (error != NULL) *error = value;
}

/* --------------------------------------------------------------- widening */

#ifdef _WIN32

/*
 * UTF-8 to UTF-16 and back, into a buffer the caller frees. NULL on failure.
 *
 * Shared rather than static: every Windows entry point that takes or returns
 * text has to do this, and the narrow API is not an option -- it speaks the
 * active code page, and a String is UTF-8 by definition. env.c uses these too.
 */
wchar_t *sl_widen(const char *utf8)
{
    if (utf8 == NULL) return NULL;

    int units = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
    if (units <= 0) return NULL;

    wchar_t *wide = (wchar_t *)malloc((size_t)units * sizeof(wchar_t));
    if (wide == NULL) sl_fail("out of memory");

    if (MultiByteToWideChar(CP_UTF8, 0, utf8, -1, wide, units) <= 0) {
        free(wide);
        return NULL;
    }
    return wide;
}

char *sl_narrow(const wchar_t *wide)
{
    if (wide == NULL) return NULL;

    int bytes = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
    if (bytes <= 0) return NULL;

    char *utf8 = (char *)malloc((size_t)bytes);
    if (utf8 == NULL) sl_fail("out of memory");

    if (WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8, bytes, NULL, NULL) <= 0) {
        free(utf8);
        return NULL;
    }
    return utf8;
}

#endif

/* ------------------------------------------------------------------ files */

/*
 * The mode string for a (mode, access) pair. The names are Standard.IO's:
 * Open requires the file to exist, Create replaces it, Append writes at the
 * end, and Update opens an existing file for both.
 */
static const char *mode_string(int32_t mode, int32_t access)
{
    _Bool readable = (access & 1) != 0;
    _Bool writable = (access & 2) != 0;

    switch (mode) {
    case 0:  /* Open */
        if (readable && writable) return "r+b";
        if (writable) return "r+b";
        return "rb";
    case 1:  /* Create */
        return readable ? "w+b" : "wb";
    case 2:  /* Append */
        return readable ? "a+b" : "ab";
    default:
        return "rb";
    }
}

void *sl_file_open(const uint8_t *path, int32_t mode, int32_t access, int32_t *error)
{
    const char *modes = mode_string(mode, access);
    FILE *file = NULL;

    errno = 0;

#ifdef _WIN32
    wchar_t *widePath = sl_widen((const char *)path);
    if (widePath == NULL) {
        report(error, SL_IO_INVALID);
        return NULL;
    }

    wchar_t wideModes[8];
    for (size_t i = 0; i < sizeof(wideModes) / sizeof(wideModes[0]); i++) {
        wideModes[i] = (wchar_t)(unsigned char)modes[i];
        if (modes[i] == '\0') break;
    }

    file = _wfopen(widePath, wideModes);
    free(widePath);
#else
    file = fopen((const char *)path, modes);
#endif

    if (file == NULL) {
        report(error, from_errno(errno));
        return NULL;
    }

    report(error, SL_IO_OK);
    return file;
}

void sl_file_close(void *handle)
{
    if (handle != NULL) fclose((FILE *)handle);
}

size_t sl_file_read(void *handle, uint8_t *buffer, size_t count, int32_t *error)
{
    if (handle == NULL) {
        report(error, SL_IO_CLOSED);
        return 0;
    }

    FILE  *file = (FILE *)handle;
    size_t read = fread(buffer, 1, count, file);

    if (read < count && ferror(file)) {
        report(error, SL_IO_UNKNOWN);
        clearerr(file);
        return read;
    }

    report(error, SL_IO_OK);
    return read;
}

size_t sl_file_write(void *handle, const uint8_t *buffer, size_t count, int32_t *error)
{
    if (handle == NULL) {
        report(error, SL_IO_CLOSED);
        return 0;
    }

    FILE  *file = (FILE *)handle;
    size_t written = fwrite(buffer, 1, count, file);

    if (written < count) {
        report(error, ferror(file) ? SL_IO_UNKNOWN : SL_IO_OK);
        clearerr(file);
        return written;
    }

    report(error, SL_IO_OK);
    return written;
}

/* origin: 0 start, 1 current, 2 end. Returns the new position, or -1. */
int64_t sl_file_seek(void *handle, int64_t offset, int32_t origin, int32_t *error)
{
    if (handle == NULL) {
        report(error, SL_IO_CLOSED);
        return -1;
    }

    int whence = origin == 1 ? SEEK_CUR : origin == 2 ? SEEK_END : SEEK_SET;

#ifdef _WIN32
    if (_fseeki64((FILE *)handle, offset, whence) != 0) {
        report(error, SL_IO_INVALID);
        return -1;
    }
    report(error, SL_IO_OK);
    return _ftelli64((FILE *)handle);
#else
    if (fseeko((FILE *)handle, (off_t)offset, whence) != 0) {
        report(error, SL_IO_INVALID);
        return -1;
    }
    report(error, SL_IO_OK);
    return (int64_t)ftello((FILE *)handle);
#endif
}

int64_t sl_file_position(void *handle)
{
    if (handle == NULL) return -1;
#ifdef _WIN32
    return _ftelli64((FILE *)handle);
#else
    return (int64_t)ftello((FILE *)handle);
#endif
}

/* The length, found by seeking to the end and back. */
int64_t sl_file_length(void *handle)
{
    if (handle == NULL) return -1;

    int64_t here = sl_file_position(handle);
    if (here < 0) return -1;

    if (sl_file_seek(handle, 0, 2, NULL) < 0) return -1;
    int64_t length = sl_file_position(handle);
    sl_file_seek(handle, here, 0, NULL);
    return length;
}

void sl_file_flush(void *handle)
{
    if (handle != NULL) fflush((FILE *)handle);
}

/* ------------------------------------------------------------------ paths */

#ifdef _WIN32
#  define SL_STAT struct _stat64
#  define sl_stat_path(wide, out) _wstat64((wide), (out))
#else
#  define SL_STAT struct stat
#endif

static _Bool stat_path(const uint8_t *path, SL_STAT *out)
{
#ifdef _WIN32
    wchar_t *wide = sl_widen((const char *)path);
    if (wide == NULL) return 0;

    _Bool ok = _wstat64(wide, out) == 0;
    free(wide);
    return ok;
#else
    return stat((const char *)path, out) == 0;
#endif
}

_Bool sl_path_exists(const uint8_t *path)
{
    SL_STAT info;
    return stat_path(path, &info);
}

_Bool sl_path_is_directory(const uint8_t *path)
{
    SL_STAT info;
    if (!stat_path(path, &info)) return 0;

#ifdef _WIN32
    return (info.st_mode & _S_IFDIR) != 0;
#else
    return S_ISDIR(info.st_mode);
#endif
}

int64_t sl_path_size(const uint8_t *path)
{
    SL_STAT info;
    if (!stat_path(path, &info)) return -1;
    return (int64_t)info.st_size;
}

/* Seconds since the epoch, or -1. */
int64_t sl_path_modified(const uint8_t *path)
{
    SL_STAT info;
    if (!stat_path(path, &info)) return -1;
    return (int64_t)info.st_mtime;
}

int32_t sl_file_delete(const uint8_t *path)
{
    errno = 0;
#ifdef _WIN32
    wchar_t *wide = sl_widen((const char *)path);
    if (wide == NULL) return SL_IO_INVALID;

    int result = _wremove(wide);
    free(wide);
#else
    int result = remove((const char *)path);
#endif
    return result == 0 ? SL_IO_OK : from_errno(errno);
}

int32_t sl_file_rename(const uint8_t *from, const uint8_t *to)
{
    errno = 0;
#ifdef _WIN32
    wchar_t *wideFrom = sl_widen((const char *)from);
    wchar_t *wideTo = sl_widen((const char *)to);
    if (wideFrom == NULL || wideTo == NULL) {
        free(wideFrom);
        free(wideTo);
        return SL_IO_INVALID;
    }

    int result = _wrename(wideFrom, wideTo);
    free(wideFrom);
    free(wideTo);
#else
    int result = rename((const char *)from, (const char *)to);
#endif
    return result == 0 ? SL_IO_OK : from_errno(errno);
}

int32_t sl_directory_create(const uint8_t *path)
{
    errno = 0;
#ifdef _WIN32
    wchar_t *wide = sl_widen((const char *)path);
    if (wide == NULL) return SL_IO_INVALID;

    int result = _wmkdir(wide);
    free(wide);
#else
    int result = mkdir((const char *)path, 0777);
#endif
    return result == 0 ? SL_IO_OK : from_errno(errno);
}

int32_t sl_directory_delete(const uint8_t *path)
{
    errno = 0;
#ifdef _WIN32
    wchar_t *wide = sl_widen((const char *)path);
    if (wide == NULL) return SL_IO_INVALID;

    int result = _wrmdir(wide);
    free(wide);
#else
    int result = rmdir((const char *)path);
#endif
    return result == 0 ? SL_IO_OK : from_errno(errno);
}

/* ------------------------------------------------------------ enumeration */

/*
 * A cursor over a directory's entries. The name it yields lives in the cursor
 * and is replaced on the next step, which is why the Stainless side copies it
 * into a String immediately.
 */
typedef struct SlDirectory {
#ifdef _WIN32
    HANDLE           find;
    WIN32_FIND_DATAW entry;
    _Bool            pending;      /* FindFirstFile already produced one */
#else
    DIR             *handle;
#endif
    char            *name;
    _Bool            isDirectory;
} SlDirectory;

void *sl_directory_open(const uint8_t *path)
{
    SlDirectory *cursor = (SlDirectory *)calloc(1, sizeof(SlDirectory));
    if (cursor == NULL) sl_fail("out of memory");

#ifdef _WIN32
    /* FindFirstFile wants a pattern, not a directory. */
    size_t   length = strlen((const char *)path);
    char    *pattern = (char *)malloc(length + 3);
    if (pattern == NULL) sl_fail("out of memory");

    memcpy(pattern, path, length);
    pattern[length] = '\\';
    pattern[length + 1] = '*';
    pattern[length + 2] = '\0';

    wchar_t *wide = sl_widen(pattern);
    free(pattern);

    if (wide == NULL) {
        free(cursor);
        return NULL;
    }

    cursor->find = FindFirstFileW(wide, &cursor->entry);
    free(wide);

    if (cursor->find == INVALID_HANDLE_VALUE) {
        free(cursor);
        return NULL;
    }
    cursor->pending = 1;
#else
    cursor->handle = opendir((const char *)path);
    if (cursor->handle == NULL) {
        free(cursor);
        return NULL;
    }
#endif

    return cursor;
}

/*
 * The next entry's name, or NULL at the end. "." and ".." are skipped, because
 * no caller has ever wanted them.
 */
const uint8_t *sl_directory_next(void *handle, _Bool *isDirectory)
{
    SlDirectory *cursor = (SlDirectory *)handle;
    if (cursor == NULL) return NULL;

    free(cursor->name);
    cursor->name = NULL;

#ifdef _WIN32
    for (;;) {
        if (!cursor->pending && !FindNextFileW(cursor->find, &cursor->entry))
            return NULL;

        cursor->pending = 0;

        const wchar_t *found = cursor->entry.cFileName;
        if (wcscmp(found, L".") == 0 || wcscmp(found, L"..") == 0) continue;

        cursor->name = sl_narrow(found);
        if (cursor->name == NULL) continue;

        cursor->isDirectory =
            (cursor->entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
        break;
    }
#else
    for (;;) {
        struct dirent *found = readdir(cursor->handle);
        if (found == NULL) return NULL;

        if (strcmp(found->d_name, ".") == 0 || strcmp(found->d_name, "..") == 0)
            continue;

        size_t length = strlen(found->d_name);
        cursor->name = (char *)malloc(length + 1);
        if (cursor->name == NULL) sl_fail("out of memory");
        memcpy(cursor->name, found->d_name, length + 1);

        cursor->isDirectory = found->d_type == DT_DIR;
        break;
    }
#endif

    if (isDirectory != NULL) *isDirectory = cursor->isDirectory;
    return (const uint8_t *)cursor->name;
}

void sl_directory_close(void *handle)
{
    SlDirectory *cursor = (SlDirectory *)handle;
    if (cursor == NULL) return;

#ifdef _WIN32
    if (cursor->find != INVALID_HANDLE_VALUE) FindClose(cursor->find);
#else
    if (cursor->handle != NULL) closedir(cursor->handle);
#endif

    free(cursor->name);
    free(cursor);
}
