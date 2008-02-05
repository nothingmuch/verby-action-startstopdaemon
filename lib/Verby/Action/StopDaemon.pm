#!/usr/bin/perl

package Verby::Action::StopDaemon;
use Moose;

use Time::HiRes qw/time/;
use File::Pid ();
use POE;

has check_delay => (
    isa => "Num",
    is  => "rw",
    default => 0.05,
);

has signal_sequence => (
    isa => "ArrayRef",
    is  => "rw",
    default => sub {
        return [
            [ TERM => 10 ],
            [ TERM => 5 ],
            [ TERM => 5 ],
            [ KILL => 1 ],
            [ KILL => 1 ],
            [ KILL => 1 ],
            [ KILL => 1 ],
            [ KILL => 1 ],
        ];
    }
);

sub do {
    my ( $self, $c ) = @_;

    my $pidfile = File::Pid->new({ file => scalar($c->pid_file) });

    POE::Session->create(
        inline_states => {
            _start => sub {
                $poe_kernel->yield( "recheck_pid" );
            },
            recheck_pid => sub {
                $self->recheck_pid( $c, $pidfile->pid, $_[HEAP] );
            },
        },
        heap => {
            signal_sequence => [ @{ $self->signal_sequence } ],
        }
    );
}

sub recheck_pid {
    my ( $self, $c, $pid, $heap ) = @_;

    if ( time < ( $heap->{checking_until} || 0 ) ) {
        unless ( $self->verify($c) ) {
            $poe_kernel->delay_set( "recheck_pid", $self->check_delay );
        } else {
            return 1; # all is good
        }
    } else {
        if ( my $next_sig = shift @{ $heap->{signal_sequence} } ) {
            my ( $sig, $wait ) = @$next_sig;
            $heap->{checking_until} = time + $wait;
            kill $sig => $pid;
            $poe_kernel->delay_set( "recheck_pid", $self->check_delay );
        } else {
            $self->confirm($c);
        }
    }
}

sub verify {
    my ( $self, $c ) = @_;

    $c->logger->info("verifying pid file " . $c->pid_file);

    my $pidfile = File::Pid->new({ file => scalar($c->pid_file) });

    if ( my $pid = $pidfile->running ) {
        $c->pid($pid);
        $c->error("$pid is alive");
        $c->logger->info("$pid is alive");
        return;
    } else {
        if ( my $pid = $pidfile->pid ) {
            $c->logger->info("$pid is written in " . $c->pid_file . " but it's dead");
        } else {
            $c->logger->info("no pid in " . $c->pid_file);
        }

        if ( -e $c->pid_file and unlink $c->pid_file ) {
            $c->logger->info("removed pid file " . $c->pid_file);
        }

        return 1;
    }
}


__PACKAGE__;

__END__
