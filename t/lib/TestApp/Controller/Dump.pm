package TestApp::Controller::Dump;

use strict;
use base 'Catalyst::Controller';

sub default : Action Private {
    my ( $self, $c ) = @_;
    $c->forward('TestApp::View::Dump');
}

sub env : Action Relative {
    my ( $self, $c ) = @_;
    $c->forward('TestApp::View::Dump', [\%ENV]);
}

sub parameters : Action Relative {
    my ( $self, $c ) = @_;
    $c->forward('TestApp::View::Dump::Parameters');
}

sub request : Action Relative {
    my ( $self, $c ) = @_;
    $c->forward('TestApp::View::Dump::Request');
}

sub response : Action Relative {
    my ( $self, $c ) = @_;
    $c->forward('TestApp::View::Dump::Response');
}

sub body : Action Relative {
    my ( $self, $c ) = @_;
    $c->forward('TestApp::View::Dump::Body');
}

1;
