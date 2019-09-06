# --
# Kernel/System/OMQ/AutoResponder/Install.pm - Module to install/uninstall the auto responder
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# Extensions Copyright © 2010-2017 OMQ GmbH, http://www.omq.de
#
# written/edited by:
# * info(at)omq(dot)de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::OMQ::AutoResponder::CheckTicketStatus;

use strict;
use warnings;

use Kernel::System::OMQ::AutoResponder::Constants;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Ticket',
    'Kernel::System::User',
    'Kernel::System::OMQ::AutoResponder::Util'
);

=head1 NAME

Kernel::System::OMQ::AutoResponder::CheckTicketStatus - Deamon Cron Task to check ticket status.

=head1 SYNOPSIS

Called every 5 minutes by Deamon

=cut

=over

=item new()

Constructor

=cut

sub new {
    my ( $Type ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item Install()

Run installation. Create all nesseccary items.

=cut

sub Run {
    my ( $Self ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    $OmqUtil->Log(
        Priority => 'notice',
        Message  => "OMQ auto-responder check ticket status.\n"
    );

    my $ApiKey  = $ConfigObject->Get('OMQ::AutoResponder::Settings::Apikey');
    my %ApiKeys = %{ $ConfigObject->Get('OMQ::AutoResponder::Settings::Apikeys') };

    $Self->CheckTicketsForApiKey( ApiKey => $ApiKey );

    while ( ( my %Item ) = each %ApiKeys ) {
        my $Key = ( values(%Item) )[0];
        if ( $Key && $Key ne '' ) {
            $Self->CheckTicketsForApiKey( ApiKey => $Key );
        }
    }

    $OmqUtil->Log(
        Priority => 'notice',
        Message  => "OMQ auto-responder ticket status checked.\n"
    );

    return $Self;
}

sub CheckTicketsForApiKey {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $ApiKey = $Param{ApiKey};

    return if ( !$ApiKey || $ApiKey eq "" );

    my $OpenTickets = $OmqUtil->SendRequest(
        Type   => 'GET',
        Url    => '/api/auto_responders/forwarded?source=OTRS',
        ApiKey => $ApiKey
    );

    my $ClosedTickets = $OmqUtil->SendRequest(
        Type   => 'GET',
        Url    => '/api/auto_responders/closed?source=OTRS',
        ApiKey => $ApiKey
    );

    # get user
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $UserID     = $UserObject->UserLookup(
        UserLogin => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DEFAULT_USER_LOGIN(),
        Silent    => 1
    );

    # set default user
    my $DefaultUserID = $ConfigObject->Get('PostmasterUserID') || 1;

    # Reopen all tickets in this list
    TICKETID:
    for my $TicketID ( @{$OpenTickets} ) {
        next TICKETID if !$TicketObject->TicketNumberLookup( TicketID => $TicketID );
        next TICKETID if !$Self->CheckTicketStateIsPending( TicketID => $TicketID );

        $TicketObject->TicketStateSet(
            State              => 'open',
            TicketID           => $TicketID,
            UserID             => $UserID,
            SendNoNotification => 1
        );

        $TicketObject->TicketOwnerSet(
            TicketID           => $TicketID,
            NewUserID          => $DefaultUserID,
            UserID             => $UserID,
            SendNoNotification => 1
        );

        $OmqUtil->Log(
            Priority => 'notice',
            Message  => "Ticket $TicketID has been opened by OMQ Auto Responder.\n"
        );
    }

    # Close all tickets in this list
    TICKETID:
    for my $TicketID ( @{$ClosedTickets} ) {
        next TICKETID if !$TicketObject->TicketNumberLookup( TicketID => $TicketID );
        next TICKETID if !$Self->CheckTicketStateIsPending( TicketID => $TicketID );

        $TicketObject->TicketStateSet(
            State              => 'closed successful',
            TicketID           => $TicketID,
            UserID             => $UserID,
            SendNoNotification => 1
        );

        $OmqUtil->Log(
            Priority => 'notice',
            Message  => "Ticket $TicketID has been closed by OMQ Auto Responder.\n"
        );
    }

    $OmqUtil->SendRequest(
        Type   => 'POST',
        Url    => '/api/auto_responders/forwarded?source=OTRS',
        Body   => $OpenTickets,
        ApiKey => $ApiKey
    );

    $OmqUtil->SendRequest(
        Type   => 'POST',
        Url    => '/api/auto_responders/closed?source=OTRS',
        Body   => $ClosedTickets,
        ApiKey => $ApiKey
    );

    return 1;
}

sub CheckTicketStateIsPending {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my %Ticket = $TicketObject->TicketGet( TicketID => $Param{TicketID} );

    return $Ticket{State} eq Kernel::System::OMQ::AutoResponder::Constants::OMQ_TICKET_STATE_NAME();
}

1;

=back
