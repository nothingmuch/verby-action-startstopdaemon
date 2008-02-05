#!/usr/bin/perl

package Verby::Action::StartDaemon;
use Moose;

with qw/Verby::Action::Run/;

use Time::HiRes qw/time/;
use File::Pid ();
use POE;

has num_checks => (
    isa => "Int",
    is  => "rw",
    default => 10,
);

has initial_check_delay => (
    isa => "Num",
    is  => "rw",
    default => 0.0625
);

has check_delay_factor => (
    isa => "Num",
    is  => "rw",
    default => 2,
);

sub do {
    my ( $self, $c ) = @_;

	$self->create_poe_session(
		c          => $c,
		cli        => $c->start_command,
        log_stdout => 1,
        log_stderr => 1,
	);
}

sub finished {
    my ( $self, $c, @args ) = @_;

    unless ( $c->verify ) {
        $self->start_delayed_verifications($c);
    }

    return 1;
}

sub start_delayed_verifications {
    my ( $self, $c ) = @_;

    POE::Session->create(
        inline_states => {
            _start => sub {
                $poe_kernel->delay_set( "recheck_pid", $self->initial_check_delay );
            },
            recheck_pid => sub {
                $self->recheck_pid( $c, $_[HEAP] );
            },
        },
        heap => {
            c                => $c,
            remaining_checks => $self->num_checks,
            check_delay      => $self->initial_check_delay,
        },
    );
}

sub recheck_pid {
    my ( $self, $c, $heap ) = @_;

    if ( $heap->{remaining_checks}-- ) {
        unless ( $self->verify($c) ) {
            my $delay = $heap->{check_delay} *= $self->check_delay_factor;
            $c->logger->info("delaying for $delay seconds for pid recheck, $heap->{remaining_checks} checks remaining" );
            $poe_kernel->delay_set( "recheck_pid", $delay );
        } else {
            return 1; # all is good
        }
    } else {
        $self->confirm($c);
    }
}

sub verify {
    my ( $self, $c ) = @_;

    $c->logger->info("verifying pid file " . $c->pid_file);

    my $pidfile = File::Pid->new({ file => scalar($c->pid_file) });

    if ( my $pid = $pidfile->running ) {
        $c->pid($pid);
        $c->logger->info("$pid is alive");
        return 1;
    } else {
        $c->logger->info("process is dead");
        if ( my $pid = $pidfile->pid ) {
            $c->error("$pid is written in " . $c->pid_file . " but it's dead");
        } else {
            $c->error("no pid in " . $c->pid_file);
        }

        if ( -e $c->pid_file and unlink $c->pid_file ) {
            $c->logger->info("removed pid file " . $c->pid_file);
        }
    }

    return;
}

__PACKAGE__;

__END__
