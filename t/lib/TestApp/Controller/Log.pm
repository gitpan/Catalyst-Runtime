package TestApp::Controller::Log;

use strict;
use base 'Catalyst::Controller';

sub debug :Local  {
    my ( $self, $c ) = @_;
    $c->log->debug('debug');
    $c->res->body( 'logged' );
}

sub info :Local  {
    my ( $self, $c ) = @_;
    $c->log->info('info');
    $c->res->body( 'logged' );
}

1;

