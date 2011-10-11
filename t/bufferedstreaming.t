use strict;
use Test::More;
use Test::Requires qw( Plack::Middleware::BufferedStreaming );
use Test::TCP;
use LWP::UserAgent;
use Plack::Builder;
use Plack::Loader;

my @tests = (
    {
        enable_buffering => 0,
        app => sub {
            return sub {
                $_[0]->([ 200, [ 'Content-Type' => 'text/plain' ], [ 'OK' ] ]);
            },
        },
        headers => HTTP::Headers->new('Content-Type', 'text/plain', 'X-Chunked', 0),
        body => 'OK',
    },
    {
        enable_buffering => 0,
        app => sub {
            return sub {
                my $writer = $_[0]->([ 200, [ 'Content-Type' => 'text/plain' ]]);
                $writer->write("O");
                $writer->write("K");
                $writer->close();
            },
        },
        headers => HTTP::Headers->new('Content-Type', 'text/plain', 'X-Chunked', 1),
        body => 'OK',
    },
    {
        enable_buffering => 1,
        app => sub {
            return sub {
                $_[0]->([ 200, [ 'Content-Type' => 'text/plain' ], [ 'OK' ] ]);
            },
        },
        headers => HTTP::Headers->new('Content-Type', 'text/plain', 'X-Chunked', 0),
        body => 'OK',
    },
    {
        enable_buffering => 1,
        app => sub {
            return sub {
                my $writer = $_[0]->([ 200, [ 'Content-Type' => 'text/plain' ]]);
                $writer->write("O");
                $writer->write("K");
                $writer->close();
            },
        },
        headers => HTTP::Headers->new('Content-Type', 'text/plain', 'X-Chunked', 0),
        body => 'OK',
    },
);

plan tests => 3 * @tests;

# pretend this is loaded (defined below)
$INC{'Test/Middleware/ResponseIsChunked.pm'} = 'Test/Middleware/ResponseIsChunked.pm';

for my $block (@tests) {
    test_tcp(
        client => sub {
            my $port = shift;

            my $ua = LWP::UserAgent->new;
            $ua->timeout(2);
            my $res = $ua->get("http://localhost:$port/");
            if ($res->is_success) {
                is($res->header($_), $block->{headers}{$_}, "$_ header passed through")
                    for keys %{ $block->{headers} };
                is $res->content, $block->{body}, "body accumulated";
            }
            else {
                fail("$_ header passed through") for keys %{ $block->{headers} };
                fail("body accumulated");
            }
        },
        server => sub {
            my $port = shift;
            my $server = Plack::Loader->load('Twiggy', port => $port, host => '127.0.0.1');
            $server->run(builder {
                enable "+Test::Middleware::ResponseIsChunked";
                enable "BufferedStreaming", stream_chunked => $block->{enable_buffering};
                $block->{app};
            });
        },
    );
};

package Test::Middleware::ResponseIsChunked;

use parent qw(Plack::Middleware);

sub call {
    my($self, $env) = @_;

    my $res = $self->app->($env);

    $self->response_cb($res, sub {
        my $res = shift;
        push @{ $res->[1] }, ('X-Chunked' => defined($res->[2]) ? 0 : 1);
    });
}
