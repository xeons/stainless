// The raw Winsock binding, measured against <winsock2.h> and then used.
//
// A constant in a binding is either the header's number or a bug that shows up
// on a Tuesday, and there is no way to tell by reading it. So probe.c beside
// this file returns what the header says and every number below is compared
// against it. The struct sizes go the same way, and so do the two `addrinfo`
// offsets -- because Windows and Linux order those two fields differently, and
// a struct with the right fields in the wrong places has exactly the right
// size.
//
// Then the binding is used: a listener, a connect, a send and a recv, straight
// through the declarations with no wrapper anywhere. Standard.Net does not go
// through this file and is not being tested here.
module Win32Sockets;

import Standard.Console;
import Standard.Text;
import Win32.Ws2_32;

extern "C" {
    long probe_af_inet();
    long probe_af_inet6();
    long probe_sock_stream();
    long probe_sock_dgram();
    long probe_ipproto_tcp();
    long probe_ipproto_udp();

    long probe_sol_socket();
    long probe_so_reuseaddr();
    long probe_so_keepalive();
    long probe_so_broadcast();
    long probe_so_rcvtimeo();
    long probe_so_sndtimeo();
    long probe_so_error();
    long probe_so_linger();
    long probe_so_exclusive();
    long probe_tcp_nodelay();
    long probe_ipv6_v6only();

    long probe_fionbio();
    long probe_sd_receive();
    long probe_sd_send();
    long probe_sd_both();

    long probe_msg_peek();
    long probe_msg_oob();
    long probe_msg_waitall();

    long probe_ai_passive();
    long probe_ai_numerichost();
    long probe_ai_numericserv();
    long probe_ni_numerichost();
    long probe_ni_numericserv();
    long probe_ni_maxhost();

    long probe_ewouldblock();
    long probe_econnrefused();
    long probe_eaddrinuse();
    long probe_enotconn();
    long probe_etimedout();

    long probe_invalid_socket();
    long probe_socket_error();

    long probe_size_wsadata();
    long probe_size_sockaddr();
    long probe_size_sockaddr_in();
    long probe_size_sockaddr_in6();
    long probe_size_sockaddr_storage();
    long probe_size_addrinfo();
    long probe_size_in_addr();
    long probe_size_in6_addr();
    long probe_size_timeval();
    long probe_size_linger();
    long probe_size_pollfd();

    long probe_offset_ai_canonname();
    long probe_offset_ai_addr();
}

/// Zero when the binding agrees with the header, and one when it does not.
/// Counted rather than kept in a variable, because a module has no mutable
/// state to keep one in.
int Check(String name, long bound, long header) {
    if (bound == header) { return 0; }

    Console.WriteLine("WRONG " + name
        + ": the binding says " + Text.FromInteger(bound)
        + ", the header says " + Text.FromInteger(header));
    return 1;
}

int Constants() {
    int wrong = 0;
    wrong = wrong + Check("AF_INET", (long)AF_INET, probe_af_inet());
    wrong = wrong + Check("AF_INET6", (long)AF_INET6, probe_af_inet6());
    wrong = wrong + Check("SOCK_STREAM", (long)SOCK_STREAM, probe_sock_stream());
    wrong = wrong + Check("SOCK_DGRAM", (long)SOCK_DGRAM, probe_sock_dgram());
    wrong = wrong + Check("IPPROTO_TCP", (long)IPPROTO_TCP, probe_ipproto_tcp());
    wrong = wrong + Check("IPPROTO_UDP", (long)IPPROTO_UDP, probe_ipproto_udp());

    wrong = wrong + Check("SOL_SOCKET", (long)SOL_SOCKET, probe_sol_socket());
    wrong = wrong + Check("SO_REUSEADDR", (long)SO_REUSEADDR, probe_so_reuseaddr());
    wrong = wrong + Check("SO_KEEPALIVE", (long)SO_KEEPALIVE, probe_so_keepalive());
    wrong = wrong + Check("SO_BROADCAST", (long)SO_BROADCAST, probe_so_broadcast());
    wrong = wrong + Check("SO_RCVTIMEO", (long)SO_RCVTIMEO, probe_so_rcvtimeo());
    wrong = wrong + Check("SO_SNDTIMEO", (long)SO_SNDTIMEO, probe_so_sndtimeo());
    wrong = wrong + Check("SO_ERROR", (long)SO_ERROR, probe_so_error());
    wrong = wrong + Check("SO_LINGER", (long)SO_LINGER, probe_so_linger());
    wrong = wrong + Check("SO_EXCLUSIVEADDRUSE", (long)SO_EXCLUSIVEADDRUSE, probe_so_exclusive());
    wrong = wrong + Check("TCP_NODELAY", (long)TCP_NODELAY, probe_tcp_nodelay());
    wrong = wrong + Check("IPV6_V6ONLY", (long)IPV6_V6ONLY, probe_ipv6_v6only());

    wrong = wrong + Check("FIONBIO", (long)FIONBIO, probe_fionbio());
    wrong = wrong + Check("SD_RECEIVE", (long)SD_RECEIVE, probe_sd_receive());
    wrong = wrong + Check("SD_SEND", (long)SD_SEND, probe_sd_send());
    wrong = wrong + Check("SD_BOTH", (long)SD_BOTH, probe_sd_both());

    wrong = wrong + Check("MSG_PEEK", (long)MSG_PEEK, probe_msg_peek());
    wrong = wrong + Check("MSG_OOB", (long)MSG_OOB, probe_msg_oob());
    wrong = wrong + Check("MSG_WAITALL", (long)MSG_WAITALL, probe_msg_waitall());

    wrong = wrong + Check("AI_PASSIVE", (long)AI_PASSIVE, probe_ai_passive());
    wrong = wrong + Check("AI_NUMERICHOST", (long)AI_NUMERICHOST, probe_ai_numerichost());
    wrong = wrong + Check("AI_NUMERICSERV", (long)AI_NUMERICSERV, probe_ai_numericserv());
    wrong = wrong + Check("NI_NUMERICHOST", (long)NI_NUMERICHOST, probe_ni_numerichost());
    wrong = wrong + Check("NI_NUMERICSERV", (long)NI_NUMERICSERV, probe_ni_numericserv());
    wrong = wrong + Check("NI_MAXHOST", (long)NI_MAXHOST, probe_ni_maxhost());

    wrong = wrong + Check("WSAEWOULDBLOCK", (long)WSAEWOULDBLOCK, probe_ewouldblock());
    wrong = wrong + Check("WSAECONNREFUSED", (long)WSAECONNREFUSED, probe_econnrefused());
    wrong = wrong + Check("WSAEADDRINUSE", (long)WSAEADDRINUSE, probe_eaddrinuse());
    wrong = wrong + Check("WSAENOTCONN", (long)WSAENOTCONN, probe_enotconn());
    wrong = wrong + Check("WSAETIMEDOUT", (long)WSAETIMEDOUT, probe_etimedout());

    wrong = wrong + Check("INVALID_SOCKET", (long)InvalidSocket, probe_invalid_socket());
    wrong = wrong + Check("SOCKET_ERROR", (long)SocketError, probe_socket_error());
    return wrong;
}

int Layout() {
    int wrong = 0;
    wrong = wrong + Check("sizeof WSADATA", (long)sizeof(WSADATA), probe_size_wsadata());
    wrong = wrong + Check("sizeof sockaddr", (long)sizeof(sockaddr), probe_size_sockaddr());
    wrong = wrong + Check("sizeof sockaddr_in", (long)sizeof(sockaddr_in), probe_size_sockaddr_in());
    wrong = wrong + Check("sizeof sockaddr_in6", (long)sizeof(sockaddr_in6), probe_size_sockaddr_in6());
    wrong = wrong + Check("sizeof sockaddr_storage", (long)sizeof(sockaddr_storage),
              probe_size_sockaddr_storage());
    wrong = wrong + Check("sizeof addrinfo", (long)sizeof(addrinfo), probe_size_addrinfo());
    wrong = wrong + Check("sizeof in_addr", (long)sizeof(in_addr), probe_size_in_addr());
    wrong = wrong + Check("sizeof in6_addr", (long)sizeof(in6_addr), probe_size_in6_addr());
    wrong = wrong + Check("sizeof timeval", (long)sizeof(timeval), probe_size_timeval());
    wrong = wrong + Check("sizeof linger", (long)sizeof(linger), probe_size_linger());
    wrong = wrong + Check("sizeof WSAPOLLFD", (long)sizeof(WSAPOLLFD), probe_size_pollfd());

    // The two fields whose order differs between Windows and Linux. Both
    // orders give the same size, so only an offset catches the wrong one.
    wrong = wrong + Check("offsetof addrinfo.ai_canonname", (long)offsetof(addrinfo, ai_canonname),
              probe_offset_ai_canonname());
    wrong = wrong + Check("offsetof addrinfo.ai_addr", (long)offsetof(addrinfo, ai_addr),
                          probe_offset_ai_addr());
    return wrong;
}

/// A loopback exchange through the declarations themselves.
int Exchange() {
    WSADATA data;
    if (WSAStartup(MakeWord(2, 2), &data) != 0) {
        Console.WriteLine("WRONG WSAStartup failed");
        return 1;
    }

    nuint server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (server == InvalidSocket) {
        Console.WriteLine("WRONG socket failed: " + Text.FromInteger((long)WSAGetLastError()));
        return 1;
    }

    sockaddr_in address;
    address.sin_family = (ushort)AF_INET;
    address.sin_port = htons(0u);                       // let the system choose
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(server, (sockaddr*)&address, (int)sizeof(sockaddr_in)) == SocketError) {
        Console.WriteLine("WRONG bind failed: " + Text.FromInteger((long)WSAGetLastError()));
        return 1;
    }

    if (listen(server, 4) == SocketError) {
        Console.WriteLine("WRONG listen failed");
        return 1;
    }

    // What port the system chose.
    sockaddr_in bound;
    int length = (int)sizeof(sockaddr_in);
    if (getsockname(server, (sockaddr*)&bound, &length) == SocketError) {
        Console.WriteLine("WRONG getsockname failed");
        return 1;
    }

    Console.WriteLine("port-chosen " + Text.FromBool(ntohs(bound.sin_port) != 0u));

    nuint client = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (connect(client, (sockaddr*)&bound, (int)sizeof(sockaddr_in)) == SocketError) {
        Console.WriteLine("WRONG connect failed: " + Text.FromInteger((long)WSAGetLastError()));
        return 1;
    }

    nuint accepted = accept(server, null, null);
    Console.WriteLine("accepted " + Text.FromBool(accepted != InvalidSocket));

    var greeting = "raw winsock";
    int sent = send(client, greeting.ToPointer(), (int)greeting.ByteLength(), 0);
    Console.WriteLine("sent " + Text.FromInteger((long)sent));

    byte[64] buffer;
    int got = recv(accepted, &buffer[0], 64, 0);
    Console.WriteLine("received " + Text.FromInteger((long)got));
    Console.WriteLine("text " + Text.FromBytes(&buffer[0], (nuint)got));

    // Shutting down the sending half: the other end sees an ending rather than
    // a reset, and recv returns 0.
    shutdown(client, SD_SEND);
    int ended = recv(accepted, &buffer[0], 64, 0);
    Console.WriteLine("ended " + Text.FromInteger((long)ended));

    closesocket(accepted);
    closesocket(client);
    closesocket(server);

    // Connecting to a port nothing listens on says why, in Winsock's numbers
    // rather than errno's.
    nuint doomed = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    sockaddr_in nothing;
    nothing.sin_family = (ushort)AF_INET;
    nothing.sin_port = htons(1u);
    nothing.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    int failed = connect(doomed, (sockaddr*)&nothing, (int)sizeof(sockaddr_in));
    Console.WriteLine("refused " + Text.FromBool(failed == SocketError));
    Console.WriteLine("refused-code " + Text.FromBool(WSAGetLastError() != 0));
    closesocket(doomed);

    WSACleanup();
    return 0;
}

int Main() {
    int wrong = Constants() + Layout() + Exchange();

    Console.WriteLine("wrong " + Text.FromInteger((long)wrong));
    return 0;
}
