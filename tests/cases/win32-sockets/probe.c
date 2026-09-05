/*
 * What <winsock2.h> actually says, so the binding can be measured against it
 * rather than against anyone's memory.
 *
 * A constant in a binding is either the header's number or a bug that will not
 * show up until the one call that uses it behaves oddly on a Tuesday. There is
 * no way to check one by reading it; there is an easy way to check one by
 * asking C.
 */

#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stddef.h>

long long probe_af_inet(void)        { return AF_INET; }
long long probe_af_inet6(void)       { return AF_INET6; }
long long probe_sock_stream(void)    { return SOCK_STREAM; }
long long probe_sock_dgram(void)     { return SOCK_DGRAM; }
long long probe_ipproto_tcp(void)    { return IPPROTO_TCP; }
long long probe_ipproto_udp(void)    { return IPPROTO_UDP; }

long long probe_sol_socket(void)     { return SOL_SOCKET; }
long long probe_so_reuseaddr(void)   { return SO_REUSEADDR; }
long long probe_so_keepalive(void)   { return SO_KEEPALIVE; }
long long probe_so_broadcast(void)   { return SO_BROADCAST; }
long long probe_so_rcvtimeo(void)    { return SO_RCVTIMEO; }
long long probe_so_sndtimeo(void)    { return SO_SNDTIMEO; }
long long probe_so_error(void)       { return SO_ERROR; }
long long probe_so_linger(void)      { return SO_LINGER; }
long long probe_so_exclusive(void)   { return SO_EXCLUSIVEADDRUSE; }
long long probe_tcp_nodelay(void)    { return TCP_NODELAY; }
long long probe_ipv6_v6only(void)    { return IPV6_V6ONLY; }

long long probe_fionbio(void)        { return (long long)FIONBIO; }
long long probe_sd_receive(void)     { return SD_RECEIVE; }
long long probe_sd_send(void)        { return SD_SEND; }
long long probe_sd_both(void)        { return SD_BOTH; }

long long probe_msg_peek(void)       { return MSG_PEEK; }
long long probe_msg_oob(void)        { return MSG_OOB; }
long long probe_msg_waitall(void)    { return MSG_WAITALL; }

long long probe_ai_passive(void)     { return AI_PASSIVE; }
long long probe_ai_numerichost(void) { return AI_NUMERICHOST; }
long long probe_ai_numericserv(void) { return AI_NUMERICSERV; }
long long probe_ni_numerichost(void) { return NI_NUMERICHOST; }
long long probe_ni_numericserv(void) { return NI_NUMERICSERV; }
long long probe_ni_maxhost(void)     { return NI_MAXHOST; }

long long probe_ewouldblock(void)    { return WSAEWOULDBLOCK; }
long long probe_econnrefused(void)   { return WSAECONNREFUSED; }
long long probe_eaddrinuse(void)     { return WSAEADDRINUSE; }
long long probe_enotconn(void)       { return WSAENOTCONN; }
long long probe_etimedout(void)      { return WSAETIMEDOUT; }

long long probe_invalid_socket(void) { return (long long)(unsigned long long)INVALID_SOCKET; }
long long probe_socket_error(void)   { return SOCKET_ERROR; }

/* And the sizes, which is where a struct one byte out is caught. */
long long probe_size_wsadata(void)          { return (long long)sizeof(WSADATA); }
long long probe_size_sockaddr(void)         { return (long long)sizeof(struct sockaddr); }
long long probe_size_sockaddr_in(void)      { return (long long)sizeof(struct sockaddr_in); }
long long probe_size_sockaddr_in6(void)     { return (long long)sizeof(struct sockaddr_in6); }
long long probe_size_sockaddr_storage(void) { return (long long)sizeof(struct sockaddr_storage); }
long long probe_size_addrinfo(void)         { return (long long)sizeof(struct addrinfo); }
long long probe_size_in_addr(void)          { return (long long)sizeof(struct in_addr); }
long long probe_size_in6_addr(void)         { return (long long)sizeof(struct in6_addr); }
long long probe_size_timeval(void)          { return (long long)sizeof(struct timeval); }
long long probe_size_linger(void)           { return (long long)sizeof(struct linger); }
long long probe_size_pollfd(void)           { return (long long)sizeof(WSAPOLLFD); }

/*
 * The two fields Windows and Linux order differently. An offset check is the
 * only thing that catches a struct whose fields are the right types in the
 * wrong places, because the size comes out identical either way.
 */
long long probe_offset_ai_canonname(void) { return (long long)offsetof(struct addrinfo, ai_canonname); }
long long probe_offset_ai_addr(void)      { return (long long)offsetof(struct addrinfo, ai_addr); }
