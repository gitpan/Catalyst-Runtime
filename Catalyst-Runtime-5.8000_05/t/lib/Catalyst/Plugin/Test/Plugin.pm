package Catalyst::Plugin::Test::Plugin;

use strict;
use warnings;
use Class::C3;

use base qw/Catalyst::Base Class::Data::Inheritable/;

 __PACKAGE__->mk_classdata('ran_setup');

sub setup {
   my $c = shift;
   $c->ran_setup('1');
}

sub  prepare {

    my $class = shift;

# Note: This use of NEXT is deliberately left here (without a use NEXT)
#       to ensure back compat, as NEXT always used to be loaded, but 
#       is now replaced by Class::C3::Adopt::NEXT.
    my $c = $class->NEXT::prepare(@_);
    $c->response->header( 'X-Catalyst-Plugin-Setup' => $c->ran_setup );

    return $c;

}

# Note: This is horrible, but Catalyst::Plugin::Server forces the body to
#       be parsed, by calling the $c->req->body method in prepare_action.
#       We need to test this, as this was broken by 5.80. See also
#       t/aggregate/live_engine_request_body.t. Better ways to test this
#       appreciated if you have suggestions :)
{
    my $have_req_body = 0;
    sub prepare_action {
        my $c = shift;
        $have_req_body++ if $c->req->body;
        $c->next::method(@_);
    }
    sub have_req_body_in_prepare_action : Local {
        my ($self, $c) = @_;
        $c->res->body($have_req_body);
    }
}

sub end : Private {
    my ($self,$c) = @_;
}

1;
