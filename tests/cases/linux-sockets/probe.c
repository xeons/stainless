/*
 * What Linux's headers actually say, so the binding can be measured against
 * them rather than against anyone's memory.
 *
 * This is the same file the Windows case has, pointed at the other platform's
 * headers -- and the numbers it returns are almost all different, which is the
 * whole reason `Linux.Sockets` says `#if LINUX` and does not pretend to be
 * POSIX in general.
 */

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stddef.h>
#include <sys/socket.h>
#include <sys/types.h>

long long probe_af_inet(void)        { return AF_INET; }
long long probe_af_inet6(void)       { return AF_INET6; }
long long probe_af_unix(void)        { return AF_UNIX; }
long long probe_sock_stream(void)    { return SOCK_STREAM; }
long long probe_sock_dgram(void)     { return SOCK_DGRAM; }
long long probe_sock_nonblock(void)  { return SOCK_NONBLOCK; }
long long probe_sock_cloexec(void)   { return SOCK_CLOEXEC; }
long long probe_ipproto_tcp(void)    { return IPPROTO_TCP; }
long long probe_ipproto_udp(void)    { return IPPROTO_UDP; }

long long probe_sol_socket(void)     { return SOL_SOCKET; }
long long probe_so_reuseaddr(void)   { return SO_REUSEADDR; }
long long probe_so_reuseport(void)   { return SO_REUSEPORT; }
long long probe_so_keepalive(void)   { return SO_KEEPALIVE; }
long long probe_so_broadcast(void)   { return SO_BROADCAST; }
long long probe_so_rcvtimeo(void)    { return SO_RCVTIMEO; }
long long probe_so_sndtimeo(void)    { return SO_SNDTIMEO; }
long long probe_so_error(void)       { return SO_ERROR; }
long long probe_so_linger(void)      { return SO_LINGER; }
long long probe_tcp_nodelay(void)    { return TCP_NODELAY; }
long long probe_ipv6_v6only(void)    { return IPV6_V6ONLY; }

long long probe_f_getfl(void)        { return F_GETFL; }
long long probe_f_setfl(void)        { return F_SETFL; }
long long probe_o_nonblock(void)     { return O_NONBLOCK; }

long long probe_shut_rd(void)        { return SHUT_RD; }
long long probe_shut_wr(void)        { return SHUT_WR; }
long long probe_shut_rdwr(void)      { return SHUT_RDWR; }

long long probe_msg_peek(void)       { return MSG_PEEK; }
long long probe_msg_oob(void)        { return MSG_OOB; }
long long probe_msg_waitall(void)    { return MSG_WAITALL; }
long long probe_msg_nosignal(void)   { return MSG_NOSIGNAL; }
long long probe_msg_dontwait(void)   { return MSG_DONTWAIT; }

long long probe_ai_passive(void)     { return AI_PASSIVE; }
long long probe_ai_numerichost(void) { return AI_NUMERICHOST; }
long long probe_ai_numericserv(void) { return AI_NUMERICSERV; }
long long probe_ni_numerichost(void) { return NI_NUMERICHOST; }
long long probe_ni_numericserv(void) { return NI_NUMERICSERV; }
long long probe_ni_maxhost(void)     { return NI_MAXHOST; }
long long probe_eai_noname(void)     { return EAI_NONAME; }
long long probe_eai_system(void)     { return EAI_SYSTEM; }

long long probe_pollin(void)         { return POLLIN; }
long long probe_pollout(void)        { return POLLOUT; }
long long probe_pollerr(void)        { return POLLERR; }
long long probe_pollhup(void)        { return POLLHUP; }
long long probe_pollnval(void)       { return POLLNVAL; }

long long probe_eagain(void)         { return EAGAIN; }
long long probe_ewouldblock(void)    { return EWOULDBLOCK; }
long long probe_econnrefused(void)   { return ECONNREFUSED; }
long long probe_eaddrinuse(void)     { return EADDRINUSE; }
long long probe_enotconn(void)       { return ENOTCONN; }
long long probe_etimedout(void)      { return ETIMEDOUT; }
long long probe_einprogress(void)    { return EINPROGRESS; }
long long probe_epipe(void)          { return EPIPE; }

long long probe_fd_setsize(void)     { return FD_SETSIZE; }

/* And the sizes, which is where a struct one byte out is caught. */
long long probe_size_sockaddr(void)         { return (long long)sizeof(struct sockaddr); }
long long probe_size_sockaddr_in(void)      { return (long long)sizeof(struct sockaddr_in); }
long long probe_size_sockaddr_in6(void)     { return (long long)sizeof(struct sockaddr_in6); }
long long probe_size_sockaddr_storage(void) { return (long long)sizeof(struct sockaddr_storage); }
long long probe_size_addrinfo(void)         { return (long long)sizeof(struct addrinfo); }
long long probe_size_in_addr(void)          { return (long long)sizeof(struct in_addr); }
long long probe_size_in6_addr(void)         { return (long long)sizeof(struct in6_addr); }
long long probe_size_timeval(void)          { return (long long)sizeof(struct timeval); }
long long probe_size_linger(void)           { return (long long)sizeof(struct linger); }
long long probe_size_pollfd(void)           { return (long long)sizeof(struct pollfd); }
long long probe_size_fd_set(void)           { return (long long)sizeof(fd_set); }

/*
 * The two fields Windows and Linux order differently. An offset check is the
 * only thing that catches a struct whose fields are the right types in the
 * wrong places, because the size comes out identical either way.
 */
long long probe_offset_ai_addr(void)      { return (long long)offsetof(struct addrinfo, ai_addr); }
long long probe_offset_ai_canonname(void) { return (long long)offsetof(struct addrinfo, ai_canonname); }
