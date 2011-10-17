use strict;
use warnings;
use AnyEvent;
use Test::More qw(no_diag);
use Test::TCP;
use IO::Socket::INET;
use Plack::Loader;

my $server = Test::TCP->new(code => sub {
    my $port = shift;
    my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');

    $server->run(sub {
        return [
            200,
            [ 'Content-Type' => 'text/plain', ],
            [ "ok\n" ],
        ];
    });
    exit 0;
});

my $port = $server->port;

my $sock1 = IO::Socket::INET->new(
    Proto => 'tcp',
    PeerAddr => '127.0.0.1',
    PeerPort => $port,
);
ok($sock1, "initial connection succeeds");

kill QUIT => $server->pid;

# soon after telling server to quit, it should no longer be possible to
# connect. keeping attempting to fail to connect for up to a few seconds
my $sock2;
for (1 .. 30) {
    $sock2 = IO::Socket::INET->new(
        Proto => 'tcp',
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
    );
    last if !$sock2;
    select undef, undef, undef, 0.1;
}
ok(!$sock2, "post-shutdown connection fails");

# ... but existing connection should still work
$sock1->print("GET / HTTP/1.0\n\n");
my $res = join '', <$sock1>;
ok(length $res, 'got some data');
like($res, qr{^HTTP/1.0 200 OK}, 'got a 200 response');

done_testing();
