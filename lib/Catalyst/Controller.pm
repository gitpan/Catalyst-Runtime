package Catalyst::Controller;

use strict;
use base qw/Catalyst::Component Catalyst::AttrContainer Class::Accessor::Fast/;

use Catalyst::Exception;
use Catalyst::Utils;
use Class::Inspector;
use NEXT;

=head1 NAME

Catalyst::Controller - Catalyst Controller base class

=head1 SYNOPSIS

  package MyApp::Controller::Search
  use base qw/Catalyst::Controller/;

  sub foo : Local { 
    my ($self,$c,@args) = @_;
    ... 
  } # Dispatches to /search/foo

=head1 DESCRIPTION

Controllers are where the actions in the Catalyst framework
reside. Each action is represented by a function with an attribute to
identify what kind of action it is. See the L<Catalyst::Dispatcher>
for more info about how Catalyst dispatches to actions.

=cut

__PACKAGE__->mk_classdata($_) for qw/_dispatch_steps _action_class/;

__PACKAGE__->_dispatch_steps( [qw/_BEGIN _AUTO _ACTION/] );
__PACKAGE__->_action_class('Catalyst::Action');

__PACKAGE__->mk_accessors( qw/_application/ );

### _app as alias
*_app = *_application;

sub _DISPATCH : Private {
    my ( $self, $c ) = @_;

    foreach my $disp ( @{ $self->_dispatch_steps } ) {
        last unless $c->forward($disp);
    }

    $c->forward('_END');
}

sub _BEGIN : Private {
    my ( $self, $c ) = @_;
    my $begin = ( $c->get_actions( 'begin', $c->namespace ) )[-1];
    return 1 unless $begin;
    $begin->dispatch( $c );
    return !@{ $c->error };
}

sub _AUTO : Private {
    my ( $self, $c ) = @_;
    my @auto = $c->get_actions( 'auto', $c->namespace );
    foreach my $auto (@auto) {
        $auto->dispatch( $c );
        return 0 unless $c->state;
    }
    return 1;
}

sub _ACTION : Private {
    my ( $self, $c ) = @_;
    if (   ref $c->action
        && $c->action->can('execute')
        && $c->req->action )
    {
        $c->action->dispatch( $c );
    }
    return !@{ $c->error };
}

sub _END : Private {
    my ( $self, $c ) = @_;
    my $end = ( $c->get_actions( 'end', $c->namespace ) )[-1];
    return 1 unless $end;
    $end->dispatch( $c );
    return !@{ $c->error };
}

sub new {
    my $self = shift;
    my $app = $_[0];
    my $new = $self->NEXT::new(@_);
    $new->_application( $app );
    return $new;
}


sub action_for {
    my ( $self, $name ) = @_;
    my $app = ($self->isa('Catalyst') ? $self : $self->_application);
    return $app->dispatcher->get_action($name, $self->action_namespace);
}

sub action_namespace {
    my ( $self, $c ) = @_;
    unless ( $c ) {
        $c = ($self->isa('Catalyst') ? $self : $self->_application);
    }
    my $hash = (ref $self ? $self : $self->config); # hate app-is-class
    return $hash->{namespace} if exists $hash->{namespace};
    return Catalyst::Utils::class2prefix( ref($self) || $self,
        $c->config->{case_sensitive} )
      || '';
}

sub path_prefix {
    my ( $self, $c ) = @_;
    unless ( $c ) {
        $c = ($self->isa('Catalyst') ? $self : $self->_application);
    }
    my $hash = (ref $self ? $self : $self->config); # hate app-is-class
    return $hash->{path} if exists $hash->{path};
    return shift->action_namespace(@_);
}


sub register_actions {
    my ( $self, $c ) = @_;
    my $class = ref $self || $self;
    my $namespace = $self->action_namespace($c);
    my %methods;
    $methods{ $self->can($_) } = $_
      for @{ Class::Inspector->methods($class) || [] };

    # Advanced inheritance support for plugins and the like
    my @action_cache;
    {
        no strict 'refs';
        for my $isa ( @{"$class\::ISA"}, $class ) {
            push @action_cache, @{ $isa->_action_cache }
              if $isa->can('_action_cache');
        }
    }

    foreach my $cache (@action_cache) {
        my $code   = $cache->[0];
        my $method = delete $methods{$code}; # avoid dupe registers
        next unless $method;
        my $attrs = $self->_parse_attrs( $c, $method, @{ $cache->[1] } );
        if ( $attrs->{Private} && ( keys %$attrs > 1 ) ) {
            $c->log->debug( 'Bad action definition "'
                  . join( ' ', @{ $cache->[1] } )
                  . qq/" for "$class->$method"/ )
              if $c->debug;
            next;
        }
        my $reverse = $namespace ? "$namespace/$method" : $method;
        my $action = $self->create_action(
            name       => $method,
            code       => $code,
            reverse    => $reverse,
            namespace  => $namespace,
            class      => $class,
            attributes => $attrs,
        );

        $c->dispatcher->register( $c, $action );
    }
}

sub create_action {
    my $self = shift;
    my %args = @_;

    my $class = (exists $args{attributes}{ActionClass}
                    ? $args{attributes}{ActionClass}[0]
                    : $self->_action_class);

    unless ( Class::Inspector->loaded($class) ) {
        require Class::Inspector->filename($class);
    }
    
    return $class->new( \%args );
}

sub _parse_attrs {
    my ( $self, $c, $name, @attrs ) = @_;

    my %raw_attributes;

    foreach my $attr (@attrs) {

        # Parse out :Foo(bar) into Foo => bar etc (and arrayify)

        if ( my ( $key, $value ) = ( $attr =~ /^(.*?)(?:\(\s*(.+?)\s*\))?$/ ) )
        {

            if ( defined $value ) {
                ( $value =~ s/^'(.*)'$/$1/ ) || ( $value =~ s/^"(.*)"/$1/ );
            }
            push( @{ $raw_attributes{$key} }, $value );
        }
    }

    my $hash = (ref $self ? $self : $self->config); # hate app-is-class

    if (exists $hash->{actions} || exists $hash->{action}) {
      my $a = $hash->{actions} || $hash->{action};
      %raw_attributes = ((exists $a->{'*'} ? %{$a->{'*'}} : ()),
                         %raw_attributes,
                         (exists $a->{$name} ? %{$a->{$name}} : ()));
    }

    my %final_attributes;

    foreach my $key (keys %raw_attributes) {

        my $raw = $raw_attributes{$key};

        foreach my $value (ref($raw) eq 'ARRAY' ? @$raw : $raw) {

            my $meth = "_parse_${key}_attr";
            if ( $self->can($meth) ) {
                ( $key, $value ) = $self->$meth( $c, $name, $value );
            }
            push( @{ $final_attributes{$key} }, $value );
        }
    }

    return \%final_attributes;
}

sub _parse_Global_attr {
    my ( $self, $c, $name, $value ) = @_;
    return $self->_parse_Path_attr( $c, $name, "/$name" );
}

sub _parse_Absolute_attr { shift->_parse_Global_attr(@_); }

sub _parse_Local_attr {
    my ( $self, $c, $name, $value ) = @_;
    return $self->_parse_Path_attr( $c, $name, $name );
}

sub _parse_Relative_attr { shift->_parse_Local_attr(@_); }

sub _parse_Path_attr {
    my ( $self, $c, $name, $value ) = @_;
    $value ||= '';
    if ( $value =~ m!^/! ) {
        return ( 'Path', $value );
    }
    elsif ( length $value ) {
        return ( 'Path', join( '/', $self->path_prefix($c), $value ) );
    }
    else {
        return ( 'Path', $self->path_prefix($c) );
    }
}

sub _parse_Regex_attr {
    my ( $self, $c, $name, $value ) = @_;
    return ( 'Regex', $value );
}

sub _parse_Regexp_attr { shift->_parse_Regex_attr(@_); }

sub _parse_LocalRegex_attr {
    my ( $self, $c, $name, $value ) = @_;
    unless ( $value =~ s/^\^// ) { $value = "(?:.*?)$value"; }
    return ( 'Regex', '^' . $self->path_prefix($c) . "/${value}" );
}

sub _parse_LocalRegexp_attr { shift->_parse_LocalRegex_attr(@_); }

sub _parse_ActionClass_attr {
    my ( $self, $c, $name, $value ) = @_;
    unless ( $value =~ s/^\+// ) {
      $value = join('::', $self->_action_class, $value );
    }
    return ( 'ActionClass', $value );
}

sub _parse_MyAction_attr {
    my ( $self, $c, $name, $value ) = @_;

    my $appclass = Catalyst::Utils::class2appclass($self);
    $value = "${appclass}::Action::${value}";

    return ( 'ActionClass', $value );
}

1;

__END__

=head1 CONFIGURATION

Like any other L<Catalyst::Component>, controllers have a config hash,
accessible through $self->config from the controller actions.  Some
settings are in use by the Catalyst framework:

=head2 namespace

This specifies the internal namespace the controller should be bound
to. By default the controller is bound to the URI version of the
controller name. For instance controller 'MyApp::Controller::Foo::Bar'
will be bound to 'foo/bar'. The default Root controller is an example
of setting namespace to '' (the null string).

=head2 prefix 

Sets 'path_prefix', as described below.

=head1 METHODS

=head2 $class->new($app, @args)

Proxies through to NEXT::new and stashes the application instance as
$self->_application.

=head2 $self->action_for('name')

Returns the Catalyst::Action object (if any) for a given method name
in this component.

=head2 $self->register_actions($c)

Finds all applicable actions for this component, creates
Catalyst::Action objects (using $self->create_action) for them and
registers them with $c->dispatcher.

=head2 $self->action_namespace($c)

Returns the private namespace for actions in this component. Defaults
to a value from the controller name (for
e.g. MyApp::Controller::Foo::Bar becomes "foo/bar") or can be
overridden from the "namespace" config key.


=head2 $self->path_prefix($c)

Returns the default path prefix for :Local, :LocalRegex and relative
:Path actions in this component. Defaults to the action_namespace or
can be overridden from the "path" config key.

=head2 $self->create_action(%args)

Called with a hash of data to be use for construction of a new
Catalyst::Action (or appropriate sub/alternative class) object.

Primarily designed for the use of register_actions.

=head2 $self->_application

=head2 $self->_app

Returns the application instance stored by C<new()>

=head1 AUTHOR

Sebastian Riedel, C<sri@oook.de>
Marcus Ramberg C<mramberg@cpan.org>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
