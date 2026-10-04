use strict;
use warnings;
use Test::More;
use Plack::Test;
use HTTP::Request;

# Package 1: Standard app (no serialiser) for text & form endpoints
{
    package TestApp::Standard;
    use Dancer2;

    query '/basic' => sub {
        return 'query ok';
    };

    query '/user/:id' => sub {
        return "User ID: " . route_parameters->get('id');
    };

    query '/search' => sub {
        my $q = body_parameters->get('q') // 'none';
        return "Search term: $q";
    };

    query '/query-only' => sub {
        return 'only query allowed';
    };
}

# Package 2: JSON-enabled app specifically for testing serialiser behaviour
{
    package TestApp::JSON;
    use Dancer2;

    set serializer => 'JSON';

    query '/json-search' => sub {
        my $data = request->data;
        unless ( ref $data eq 'HASH' ) {
            return status 400 => { error => 'Invalid JSON' };
        }
        return { filter => $data->{filter} // 'none' };
    };
}

my $test_std  = Plack::Test->create( TestApp::Standard->to_app );
my $test_json = Plack::Test->create( TestApp::JSON->to_app );

subtest 'Basic QUERY route dispatch' => sub {
    my $req = HTTP::Request->new( QUERY => '/basic' );
    my $res = $test_std->request($req);

    is( $res->code, 200, 'Returns 200 OK' );
    is( $res->content, 'query ok', 'Response body matches' );
};

subtest 'QUERY route with path parameters' => sub {
    my $req = HTTP::Request->new( QUERY => '/user/42' );
    my $res = $test_std->request($req);

    is( $res->code, 200, 'Returns 200 OK' );
    is( $res->content, 'User ID: 42', 'Route parameter correctly extracted' );
};

subtest 'QUERY request with form-encoded body payload' => sub {
    my $req = HTTP::Request->new(
        QUERY => '/search',
        [ 'Content-Type' => 'application/x-www-form-urlencoded' ],
        'q=dancer2+query'
    );
    my $res = $test_std->request($req);

    is( $res->code, 200, 'Returns 200 OK' );
    is( $res->content, 'Search term: dancer2 query', 'Form parameters parsed correctly' );
};

subtest 'QUERY request with JSON payload' => sub {
    my $json_payload = '{"filter":"active_users"}';
    my $req = HTTP::Request->new(
        QUERY => '/json-search',
        [ 'Content-Type' => 'application/json' ],
        $json_payload
    );
    my $res = $test_json->request($req);

    is( $res->code, 200, 'Returns 200 OK' );
    like( $res->content, qr/"filter"\s*:\s*"active_users"/, 'JSON body deserialised into request->data' );
};

subtest 'HTTP method matching isolation' => sub {
    my $req_get = HTTP::Request->new( GET => '/query-only' );
    my $res_get = $test_std->request($req_get);

    is( $res_get->code, 404, 'GET request to query-only route returns 404' );

    my $req_query = HTTP::Request->new( QUERY => '/query-only' );
    my $res_query = $test_std->request($req_query);

    is( $res_query->code, 200, 'QUERY request succeeds on query route' );
};

done_testing;
