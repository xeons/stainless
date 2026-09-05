// The raw Linux socket binding, measured against the headers and then used.
//
// The same case as `win32-sockets`, pointed at the other platform -- and
// almost every number it checks is a different number, which is exactly why
// `Linux.Sockets` says `#if LINUX` rather than `#if UNIX`. `AF_INET6` is 10
// here and 23 there; `SOL_SOCKET` is 1 here and 0xFFFF there; `NI_NUMERICHOST`
// is 1 here and 2 there, so passing one platform's flag to the other's
// `getnameinfo` asks a different question and gets a plausible wrong answer.
//
// Then the binding is used: a listener, a connect, a send and a recv, straight
// through the declarations with no wrapper anywhere. Standard.Net does not go
// through this file and is not being tested here.
module LinuxSockets;

import Standard.Console;
import Standard.Text;
import Linux.Sockets;

extern "C" {
    long probe_af_inet();
    long probe_af_inet6();
    long probe_af_unix();
    long probe_sock_stream();
    long probe_sock_dgram();
    long probe_sock_nonblock();
    long probe_sock_cloexec();
    long probe_ipproto_tcp();
    long probe_ipproto_udp();

    long probe_sol_socket();
    long probe_so_reuseaddr();
    long probe_so_reuseport();
    long probe_so_keepalive();
    long probe_so_broadcast();
    long probe_so_rcvtimeo();
    long probe_so_sndtimeo();
    long probe_so_error();
    long probe_so_linger();
    long probe_tcp_nodelay();
    long probe_ipv6_v6only();

    long probe_f_getfl();
    long probe_f_setfl();
    long probe_o_nonblock();

    long probe_shut_rd();
    long probe_shut_wr();
    long probe_shut_rdwr();

    long probe_msg_peek();
    long probe_msg_oob();
    long probe_msg_waitall();
    long probe_msg_nosignal();
    long probe_msg_dontwait();

    long probe_ai_passive();
    long probe_ai_numerichost();
    long probe_ai_numericserv();
    long probe_ni_numerichost();
    long probe_ni_numericserv();
    long probe_ni_maxhost();
    long probe_eai_noname();
    long probe_eai_system();

    long probe_pollin();
    long probe_pollout();
    long probe_pollerr();
    long probe_pollhup();
    long probe_pollnval();

    long probe_eagain();
    long probe_ewouldblock();
    long probe_econnrefused();
    long probe_eaddrinuse();
    long probe_enotconn();
    long probe_etimedout();
    long probe_einprogress();
    long probe_epipe();

    long probe_fd_setsize();

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
    long probe_size_fd_set();

    long probe_offset_ai_addr();
    long probe_offset_ai_canonname();
}

/// Zero when the binding agrees with the header, and one when it does not.
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
    wrong = wrong + Check("AF_UNIX", (long)AF_UNIX, probe_af_unix());
    wrong = wrong + Check("SOCK_STREAM", (long)SOCK_STREAM, probe_sock_stream());
    wrong = wrong + Check("SOCK_DGRAM", (long)SOCK_DGRAM, probe_sock_dgram());
    wrong = wrong + Check("SOCK_NONBLOCK", (long)SOCK_NONBLOCK, probe_sock_nonblock());
    wrong = wrong + Check("SOCK_CLOEXEC", (long)SOCK_CLOEXEC, probe_sock_cloexec());
    wrong = wrong + Check("IPPROTO_TCP", (long)IPPROTO_TCP, probe_ipproto_tcp());
    wrong = wrong + Check("IPPROTO_UDP", (long)IPPROTO_UDP, probe_ipproto_udp());

    wrong = wrong + Check("SOL_SOCKET", (long)SOL_SOCKET, probe_sol_socket());
    wrong = wrong + Check("SO_REUSEADDR", (long)SO_REUSEADDR, probe_so_reuseaddr());
    wrong = wrong + Check("SO_REUSEPORT", (long)SO_REUSEPORT, probe_so_reuseport());
    wrong = wrong + Check("SO_KEEPALIVE", (long)SO_KEEPALIVE, probe_so_keepalive());
    wrong = wrong + Check("SO_BROADCAST", (long)SO_BROADCAST, probe_so_broadcast());
    wrong = wrong + Check("SO_RCVTIMEO", (long)SO_RCVTIMEO, probe_so_rcvtimeo());
    wrong = wrong + Check("SO_SNDTIMEO", (long)SO_SNDTIMEO, probe_so_sndtimeo());
    wrong = wrong + Check("SO_ERROR", (long)SO_ERROR, probe_so_error());
    wrong = wrong + Check("SO_LINGER", (long)SO_LINGER, probe_so_linger());
    wrong = wrong + Check("TCP_NODELAY", (long)TCP_NODELAY, probe_tcp_nodelay());
    wrong = wrong + Check("IPV6_V6ONLY", (long)IPV6_V6ONLY, probe_ipv6_v6only());

    wrong = wrong + Check("F_GETFL", (long)F_GETFL, probe_f_getfl());
    wrong = wrong + Check("F_SETFL", (long)F_SETFL, probe_f_setfl());
    wrong = wrong + Check("O_NONBLOCK", (long)O_NONBLOCK, probe_o_nonblock());

    wrong = wrong + Check("SHUT_RD", (long)SHUT_RD, probe_shut_rd());
    wrong = wrong + Check("SHUT_WR", (long)SHUT_WR, probe_shut_wr());
    wrong = wrong + Check("SHUT_RDWR", (long)SHUT_RDWR, probe_shut_rdwr());

    wrong = wrong + Check("MSG_PEEK", (long)MSG_PEEK, probe_msg_peek());
    wrong = wrong + Check("MSG_OOB", (long)MSG_OOB, probe_msg_oob());
    wrong = wrong + Check("MSG_WAITALL", (long)MSG_WAITALL, probe_msg_waitall());
    wrong = wrong + Check("MSG_NOSIGNAL", (long)MSG_NOSIGNAL, probe_msg_nosignal());
    wrong = wrong + Check("MSG_DONTWAIT", (long)MSG_DONTWAIT, probe_msg_dontwait());

    wrong = wrong + Check("AI_PASSIVE", (long)AI_PASSIVE, probe_ai_passive());
    wrong = wrong + Check("AI_NUMERICHOST", (long)AI_NUMERICHOST, probe_ai_numerichost());
    wrong = wrong + Check("AI_NUMERICSERV", (long)AI_NUMERICSERV, probe_ai_numericserv());
    wrong = wrong + Check("NI_NUMERICHOST", (long)NI_NUMERICHOST, probe_ni_numerichost());
    wrong = wrong + Check("NI_NUMERICSERV", (long)NI_NUMERICSERV, probe_ni_numericserv());
    wrong = wrong + Check("NI_MAXHOST", (long)NI_MAXHOST, probe_ni_maxhost());
    wrong = wrong + Check("EAI_NONAME", (long)EAI_NONAME, probe_eai_noname());
    wrong = wrong + Check("EAI_SYSTEM", (long)EAI_SYSTEM, probe_eai_system());

    wrong = wrong + Check("POLLIN", (long)POLLIN, probe_pollin());
    wrong = wrong + Check("POLLOUT", (long)POLLOUT, probe_pollout());
    wrong = wrong + Check("POLLERR", (long)POLLERR, probe_pollerr());
    wrong = wrong + Check("POLLHUP", (long)POLLHUP, probe_pollhup());
    wrong = wrong + Check("POLLNVAL", (long)POLLNVAL, probe_pollnval());

    wrong = wrong + Check("EAGAIN", (long)EAGAIN, probe_eagain());
    wrong = wrong + Check("EWOULDBLOCK", (long)EWOULDBLOCK, probe_ewouldblock());
    wrong = wrong + Check("ECONNREFUSED", (long)ECONNREFUSED, probe_econnrefused());
    wrong = wrong + Check("EADDRINUSE", (long)EADDRINUSE, probe_eaddrinuse());
    wrong = wrong + Check("ENOTCONN", (long)ENOTCONN, probe_enotconn());
    wrong = wrong + Check("ETIMEDOUT", (long)ETIMEDOUT, probe_etimedout());
    wrong = wrong + Check("EINPROGRESS", (long)EINPROGRESS, probe_einprogress());
    wrong = wrong + Check("EPIPE", (long)EPIPE, probe_epipe());

    wrong = wrong + Check("FD_SETSIZE", (long)FD_SETSIZE, probe_fd_setsize());
    return wrong;
}

int Layout() {
    int wrong = 0;
    wrong = wrong + Check("sizeof sockaddr", (long)sizeof(sockaddr), probe_size_sockaddr());
    wrong = wrong + Check("sizeof sockaddr_in", (long)sizeof(sockaddr_in),
                          probe_size_sockaddr_in());
    wrong = wrong + Check("sizeof sockaddr_in6", (long)sizeof(sockaddr_in6),
                          probe_size_sockaddr_in6());
    wrong = wrong + Check("sizeof sockaddr_storage", (long)sizeof(sockaddr_storage),
                          probe_size_sockaddr_storage());
    wrong = wrong + Check("sizeof addrinfo", (long)sizeof(addrinfo), probe_size_addrinfo());
    wrong = wrong + Check("sizeof in_addr", (long)sizeof(in_addr), probe_size_in_addr());
    wrong = wrong + Check("sizeof in6_addr", (long)sizeof(in6_addr), probe_size_in6_addr());
    wrong = wrong + Check("sizeof timeval", (long)sizeof(timeval), probe_size_timeval());
    wrong = wrong + Check("sizeof linger", (long)sizeof(linger), probe_size_linger());
    wrong = wrong + Check("sizeof pollfd", (long)sizeof(pollfd), probe_size_pollfd());
    wrong = wrong + Check("sizeof fd_set", (long)sizeof(fd_set), probe_size_fd_set());

    // The two fields whose order differs between Linux and Windows. Both
    // orders give the same size, so only an offset catches the wrong one.
    wrong = wrong + Check("offsetof addrinfo.ai_addr", (long)offsetof(addrinfo, ai_addr),
                          probe_offset_ai_addr());
    wrong = wrong + Check("offsetof addrinfo.ai_canonname",
                          (long)offsetof(addrinfo, ai_canonname),
                          probe_offset_ai_canonname());
    return wrong;
}

/// A loopback exchange through the declarations themselves.
int Exchange() {
    int server = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (server < 0) {
        Console.WriteLine("WRONG socket failed: " + Text.FromInteger((long)Errno()));
        return 1;
    }

    sockaddr_in address;
    address.sin_family = (ushort)AF_INET;
    address.sin_port = htons(0u);                       // let the system choose
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(server, (sockaddr*)&address, (uint)sizeof(sockaddr_in)) < 0) {
        Console.WriteLine("WRONG bind failed: " + Text.FromInteger((long)Errno()));
        return 1;
    }

    if (listen(server, 4) < 0) {
        Console.WriteLine("WRONG listen failed: " + Text.FromInteger((long)Errno()));
        return 1;
    }

    sockaddr_in bound;
    uint length = (uint)sizeof(sockaddr_in);
    if (getsockname(server, (sockaddr*)&bound, &length) < 0) {
        Console.WriteLine("WRONG getsockname failed");
        return 1;
    }

    Console.WriteLine("port-chosen " + Text.FromBool(ntohs(bound.sin_port) != 0u));

    int client = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (connect(client, (sockaddr*)&bound, (uint)sizeof(sockaddr_in)) < 0) {
        Console.WriteLine("WRONG connect failed: " + Text.FromInteger((long)Errno()));
        return 1;
    }

    int accepted = accept(server, null, null);
    Console.WriteLine("accepted " + Text.FromBool(accepted >= 0));

    var greeting = "raw sockets";

    // MSG_NOSIGNAL, because a write to a closed peer otherwise raises SIGPIPE
    // and kills the process. Windows has no such signal and so no such flag.
    long sent = send(client, greeting.ToPointer(), greeting.ByteLength(), MSG_NOSIGNAL);
    Console.WriteLine("sent " + Text.FromInteger(sent));

    byte[64] buffer;
    long got = recv(accepted, &buffer[0], 64u, 0);
    Console.WriteLine("received " + Text.FromInteger(got));
    Console.WriteLine("text " + Text.FromBytes(&buffer[0], (nuint)got));

    shutdown(client, SHUT_WR);
    long ended = recv(accepted, &buffer[0], 64u, 0);
    Console.WriteLine("ended " + Text.FromInteger(ended));

    close(accepted);
    close(client);
    close(server);

    // Connecting to a port nothing listens on says why, through errno rather
    // than through a return value.
    int doomed = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    sockaddr_in nothing;
    nothing.sin_family = (ushort)AF_INET;
    nothing.sin_port = htons(1u);
    nothing.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    int failed = connect(doomed, (sockaddr*)&nothing, (uint)sizeof(sockaddr_in));
    Console.WriteLine("refused " + Text.FromBool(failed < 0));
    Console.WriteLine("refused-code " + Text.FromBool(Errno() == ECONNREFUSED));
    close(doomed);

    return 0;
}

int Main() {
    int wrong = Constants() + Layout() + Exchange();

    Console.WriteLine("wrong " + Text.FromInteger((long)wrong));
    return 0;
}
