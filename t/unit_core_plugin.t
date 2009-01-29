#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 22;

use lib 't/lib';

{

    package Faux::Plugin;

    sub new { bless {}, shift }
    my $count = 1;
    sub count { $count++ }
}

use Catalyst::Test qw/PluginTestApp/;

ok( get("/compile_time_plugins"), "get ok" );
# FIXME - Run time plugin support is insane, and should be removed
#         for Catalyst 5.9
ok( get("/run_time_plugins"),     "get ok" );

use_ok 'TestApp';
my @expected = qw(
  Catalyst::Plugin::Test::Errors
  Catalyst::Plugin::Test::Headers
  Catalyst::Plugin::Test::Inline
  Catalyst::Plugin::Test::Plugin
  TestApp::Plugin::AddDispatchTypes
  TestApp::Plugin::FullyQualified
);

# Faux::Plugin is no longer reported
is_deeply [ TestApp->registered_plugins ], \@expected,
  'registered_plugins() should only report the plugins for the current class';
