
use strict;
use warnings;
use Data::Dumper;
package WWW::Spotify;


# ABSTRACT: Spotify Web API Wrapper

use Moose;

BEGIN {
    $WWW::Spotify::VERSION = "0.001";
}

use Data::Dumper;
use URI;
use URI::Escape;
use WWW::Mechanize;
use JSON::XS;
use JSON::Path;
use XML::Simple;
use HTTP::Headers;
use Scalar::Util;
use File::Basename;
use IO::CaptureOutput qw( capture qxx qxy );
#use Digest::MD5::File qw( file_md5_hex url_md5_hex );

has 'result_format' => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'json'
);

has 'grab_response_header' => (
    is      => 'rw',
    isa => 'Int',
    default => 0
);

has 'results' => (
    is       => 'rw',
    isa      => 'Int',
    default  => '15'
);

has 'debug' => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0
);

has 'uri_scheme' => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'https'
);

has uri_hostname => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'api.spotify.com'
);

has uri_domain_path => (
    is       => 'rw',
    isa      => 'Str',
    default  => 'api'
);

has call_type => (
    is       => 'rw',
    isa      => 'Str'
);

has auto_json_decode => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0
);

has auto_xml_decode => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0
);

has last_result => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

has last_error => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

has response_headers => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

has problem => (
    is        => 'rw',
    isa       => 'Str',
    default   => q{}
);

my %api_call_options = (

        '/v1/albums/{id}' => {
            info => 'Get an album' ,
            type => 'GET',
            method => 'album'
        },

        '/v1/albums?ids={ids}' => {
            info => 'Get several albums' ,
            type => 'GET',
            method => 'albums',
            params => [ 'limit' , 'offset' ]
        },

        '/v1/albums/{id}/tracks' => {
            info => "Get an album's tracks" ,
            type => 'GET',
            method => 'album_tracks'
        },

        '/v1/artists/{id}' => {
            info => "Get an artist",
            type => 'GET',
            method => 'artist'
        },

	'/v1/artists?ids={ids}' => {
            info => "Get several artists",
            type => 'GET',
            method => 'artists'
        },
        
	'/v1/artists/{id}/albums' => {
            info => "Get an artist's albums",
            type => 'GET',
            method => 'artist_albums',
            params => [ 'limit' , 'offset' , 'country' , 'album_type' ]
        },
        
        '/v1/artists/{id}/top-tracks?country={country}' => {
            info => "Get an artist's top tracks",
            type => 'GET',
            method => 'artist_top_tracks',
            params => [ 'country' ]
        },

        # adding q and type to url unlike example since they are both required
	'/v1/search?q={q}&type={type}' => {
            info => "Search for an item",
            type => 'GET',
            method => 'search',
            params => [ 'limit' , 'offset' , 'q' , 'type' ]
        },
        
	'/v1/tracks/{id}' => {
            info => "Get a track",
            type => 'GET',
            method => 'track'
        },
        
	'/v1/tracks?ids={ids}' => {
            info =>  "Get several tracks",
            type => 'GET',
            method => 'tracks'
        },

	'/v1/users/{user_id}' => {
            info => "Get a user's profile",
            type => 'GET',
            method => 'user'
        },

        '/v1/me' => {

            info => "Get current user's profile",
            type => 'GET',
            method => 'me'
        },
        
	'/v1/users/{user_id}/playlists' => {
            info => "Get a list of a user's playlists",
            type => 'GET',
            method => 'user_playlist'
        },
        
	'/v1/users/{user_id}/playlists/{playlist_id}' => {
            info => "Get a playlist",
            type => 'GET',
            method => ''
        },

        '/v1/users/{user_id}/playlists/{playlist_id}/tracks' => {
            info => "Get a playlist's tracks",
            type => 'POST',
            method => ''
        },
        

        '/v1/users/{user_id}/playlists'	=> {
            info => 'Create a playlist',
            type => 'POST',
            method => ''
        },

        '/v1/users/{user_id}/playlists/{playlist_id}/tracks' => {
            info => 'Add tracks to a playlist',
            type => 'POST',
            method => ''
        }
                        );

my %method_to_uri = ();

foreach my $key (keys %api_call_options) {
    next if $api_call_options{$key}->{method} eq '';
    $method_to_uri{$api_call_options{$key}->{method}} = $key;
}

# print Dumper(\%method_to_uri);

sub is_valid_json {
    my ($self,$json,$caller) = @_;
    eval {
        decode_json $json;    
    };
    
    if ($@) {
        $self->last_error("invalid josn passed into $caller");
        return 0;
    } else {
        return 1;
    }
}

sub send_get_request {
    # need to build the URL here
    my $self = shift;
    
    my $attributes = shift;
    
    my $uri_params = '';
    
    if (defined $attributes->{extras} and ref $attributes->{extras} eq 'HASH') {
        my @tmp = ();
        
        foreach my $key (keys %{$attributes->{extras}}) {
            push @tmp , "$key=$attributes->{extras}{$key}";
        }
        $uri_params = join('&',@tmp);
    }
    
    
    if (exists $attributes->{format} && $attributes->{format} =~ /json|xml|xspf|jsonp/) {
        $self->result_format($attributes->{format});
        delete $attributes->{format};
    }
    
    # my $url = $self->build_url_base($call_type);
    
    my $url = $self->uri_scheme();
    
    # the ://
    $url .= "://";
    
    # the domain
    $url .= $self->uri_hostname();
    
    my $path = $method_to_uri{$attributes->{method}};
    if ($path) {
        
        warn "raw: $path" if $self->debug();
        
        if ($path =~ /search/ && $attributes->{method} eq 'search') {
            $path =~ s/\{q\}/$attributes->{q}/;
            $path =~ s/\{type\}/$attributes->{type}/;
        } elsif ($path =~ m/\{id\}/ && exists $attributes->{params}{id}) {
            $path =~ s/\{id\}/$attributes->{params}{id}/;   
        } elsif ($path =~ m/\{ids\}/ && exists $attributes->{params}{ids}) {
            $path =~ s/\{ids\}/$attributes->{params}{ids}/;
        }
        
        if ($path =~ m/\{country\}/) {
            $path =~ s/\{country\}/$attributes->{params}{country}/;
        }
        
        if ($path =~ m/\{user_id\}/ && exists $attributes->{params}{user_id}) {
            $path =~ s/\{user_id\}/$attributes->{params}{user_id}/;   
        }
        
        if ($path =~ m/\{playlist_id\}/ && exists $attributes->{params}{playlist_id}) {
            $path =~ s/\{playlist_id\}/$attributes->{params}{playlist_id}/;   
        }
        
        
        warn "modified: $path" if $self->debug();
    }
    
    $url .= $path;
    
    # now we need to address the "extra" attributes if any
    if ($uri_params) {
        my $start_with = '?';
        if ($url =~ /\?/) {
            $start_with = '&';
        }
        $url .= $start_with . $uri_params;
    }
    
    
    my $need_auth = 0;
    if ($need_auth) {
        #code
        # ensure we have a semi valid api key stashed away
        if ($self->_have_valid_api_key() == 0) {
            return "won't send requests without a valid api key";
        }
        # since it is a GET we can ? it
        $url .= "?";
    
        # add the api key since it should always be sent
        $url .= "api_key=" . $self->api_key();
    
        # add the format
    
        $url .= "&format=" . $self->result_format();
    }
    
    warn "$url\n" if $self->debug;
    local $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
    my $mech = WWW::Mechanize->new( autocheck => 0 );
    $mech->get( $url );
    
    if ($self->grab_response_header() == 1) {
        $self->_set_response_headers($mech);
    }
    return $self->format_results($mech->content);
    
}

sub _set_response_headers {
    my $self = shift;
    my $mech = shift;
    
    my $hd;
    capture { $mech->dump_headers(); } \$hd;

    $self->response_headers($hd);
    return;
}

sub format_results {
    my $self = shift;
    my $content = shift;
    
    # want to store the result in case
    # we want to interact with it via a helper method
    $self->last_result($content);
    
    # FIX ME / TEST ME
    # vefify both of these work and return the *same* perl hash
    
    # when / how should we check the status? Do we need to?
    # if so then we need to create another method that will
    # manage a Sucess vs. Fail request
    
    if ($self->auto_json_decode && $self->result_format eq 'json' ) {
        return decode_json $content;
    }

    if ($self->auto_xml_decode && $self->result_format eq 'xml' ) {
        # FIX ME
        my $xs = XML::Simple->new();
        return $xs->XMLin($content);
    }
    
    # results are not altered in this cass and would be either
    # json or xml instead of a perl data structure
    
    return $content;
}

sub get {
    
    # This seemed like a simple enough method
    # but everything I tried resulted in unacceptable
    # trade offs and explict defining of the structures
    # The new method, which I hope I remember when I
    # revisit it, was to use JSON::Path
    # It is an awesome module, but a little heavy
    # on dependencies.  However I would not have been
    # able to do this in so few lines without it
    
    # Making a generalization here
    # if you use a * you are looking for an array
    # if you don't have an * you want the first 1 (or should I say you get the first 1)
   
    my ($self,@return) = @_;
    # my @return = @_;

    my @out;
    
    my $result = decode_json $self->last_result(); 
    
    my $search_ref = $result;
    
    warn Dumper($result) if $self->debug();
    
    foreach my $key (@return) {
        my $type = 'value';
        if ($key =~ /\*\]/) {
            $type = 'values';
        }
        
        my $jpath = JSON::Path->new("\$.$key");
        
        my @t_arr = $jpath->$type($result);
        
        if ($type eq 'value') {
            push @out , $t_arr[0];
        } else {
            push @out , \@t_arr;
        }
    }
    if (wantarray) {
        return @out;    
    } else {
        return $out[0];
    }
    

}

sub build_url_base {
    # first the uri type
    my $self = shift;
    my $call_type = shift || $self->call_type();    
  
    my $url = $self->uri_scheme();
    
    # the ://
    $url .= "://";
    
    # the domain
    $url .= $self->uri_hostname();
    
    # the path
    if ( $self->uri_domain_path() ) {
        $url .= "/" . $self->uri_domain_path();
    }
 
    return $url;
}

#-- spotify specific methods

sub album {
    my $self = shift;
    my $id = shift;

    return $self->send_get_request(
        { method => 'album',
          params => { 'id' => $id }
        }
    );
}

sub albums {
    my $self = shift;
    my $ids = shift;

    return $self->send_get_request(
        { method => 'albums',
          params => { 'ids' => $ids }
        }
    );

}

sub album_tracks {
    my $self = shift;
    my $album_id = shift;
    my $extras    = shift;

    return $self->send_get_request(
        { method => 'album_tracks',
          params => { 'id' => $album_id },
          extras => $extras
        }
    );
        
}

sub artist {
    my $self = shift;
    my $id = shift;
    
    return $self->send_get_request(
        { method => 'artist',
          params => { 'id' => $id }
        }
    );            

}

sub artists {
    my $self = shift;
    my $artists = shift;
    
    return $self->send_get_request(
        { method => 'artists',
          params => { 'ids' => $artists }
        }
    );

}

sub artist_albums {
    my $self = shift;
    my $artist_id = shift;
    my $extras = shift;
    
    return $self->send_get_request(
        { method => 'artist_albums',
          params => { 'id' => $artist_id },
          extras => $extras  
        }
    );
    
}

sub artist_top_tracks {
    my $self = shift;
    my $artist_id = shift;
    my $country = shift;

    return $self->send_get_request(
        { method => 'artist_top_tracks',
          params => { 'id' => $artist_id,
                      'country' => $country
                     }
        }
    );

}

sub me {
    my $self = shift;
    return;
}

sub next_result_set {
    my $self = shift;
    my $result = shift;
    return;
}

sub previous_result_set {
    my $self = shift;
    my $result = shift;
    return;
}

sub search {
    my $self = shift;
    my $q    = shift;
    my $type = shift;
    my $extras = shift;

    return $self->send_get_request(
        { method => 'search',
          q      => $q,
          type   => $type,
          extras => $extras
          
        }
    );
   
}

sub track {
    my $self = shift;
    my $id = shift;
    return $self->send_get_request(
        { method => 'track',
          params => { 'id' => $id }
        }
    ); 

}

sub tracks {
    my $self = shift;
    my $tracks = shift;
    
    return $self->send_get_request(
        { method => 'tracks',
          params => { 'ids' => $tracks }
        }
    );
    
}

sub user {
    my $self = shift;
    my $user_id = shift;
    return $self->send_get_request(
        { method => 'user',
          params => { 'user_id' => $user_id }
        }
    ); 

}

sub user_playlist {
    my $self = shift;
    return;
}

sub user_playlist_add_tracks {
    my $self = shift;
    return;
}

sub user_playlist_create {
    my $self = shift;
    return;
}

sub user_playlists {
    my $self = shift;
    return;
}

1;

__END__

=pod

=head1 NAME

WWW::Spotify - Spotify Web API Wrapper

=head1 VERSION

version 0.001

=head1 SYNOPSIS

    use WWW::Spotify;
 
    my $spotify = WWW::Spotify->new();
    
    my $spotify = WWW::Spotify->new();
    
    my $result;
    
    $result = $spotify->album('0sNOF9WDwhWunNAHPD3Baj');
    
    # $result is a json structure, you can operate on it directly
    # or you can use the "get" method see below
    
    $result = $spotify->albums( '41MnTivkwTO3UUJ8DrqEJJ,6JWc4iAiJ9FjyK0B59ABb4,6UXCm6bOO4gFlDQZV5yL37' );
    
    $result = $spotify->album_tracks( '6akEvsycLGftJxYudPjmqK',
    {
        limit => 0,
        offset => 1
        
    }
    ); 
    
    $result = $spotify->artist( '0LcJLqbBmaGUft1e9Mm8HV' );
    
    my $artists_multiple = '0oSGxfWSnnOXhD2fKuz2Gy,3dBVyJ7JuOMt4GE9607Qin';
    
    $result = $spotify->artists( $artists_multiple );
    
    $result = $spotify->artist_albums( '1vCWHaC5f2uS3yhpwWbIA6' ,
                        { album_type => 'single',
                          # country => 'US',
                          limit   => 2,
                          offset  => 0
                        }  );
    
    $result = $spotify->track( '0eGsygTp906u18L0Oimnem' );
    
    $result = $spotify->tracks( '0eGsygTp906u18L0Oimnem,1lDWb6b6ieDQ2xT7ewTC3G' );
    
    $result = $spotify->artist_top_tracks( '43ZHCT0cAZBISjO8DG9PnE', # artist id
                                            'SE' # country
                                            );
    
    $result = $spotify->search(
                        'tania bowra' ,
                        'artist' ,
                        { limit => 15 , offset => 0 }
    );
    
    $result = $spotify->user( 'glennpmcdonald' );

=head2 get

Returns a specific item or array of items from the JSON result of the
last action.

    $result = $spotify->search(
                        'tania bowra' ,
                        'artist' ,
                        { limit => 15 , offset => 0 }
    );
 
 my $image_url = $spotify->get( 'artists.items[0].images[0].url' );

JSON::Path is the underlying library that actually parses the JSON.

=head1 DESCRIPTION

Wrapper for the Spotify Web API.

https://developer.spotify.com/web-api/

Have access to a JSON viewer to help develop and debug. The Chrome JSON viewer is
very good and provides the exact path of the item within the JSON in the lower left
of the screen as you mouse over an element.

=head1 NAME

WWW::Spotify

=head1 THANKS

Paul Lamere at The Echo Nest / Spotify

All the great Perl community members that keep Perl fun

=head1 AUTHOR

Aaron Johnson <aaronjjohnson@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Aaron Johnson.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
