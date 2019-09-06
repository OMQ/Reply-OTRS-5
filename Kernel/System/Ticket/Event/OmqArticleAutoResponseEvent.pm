# --
# Kernel/System/Ticket/Event/OmqArticleAutoResponseEvent.pm - Event handler to notify server about sent auto response
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

package Kernel::System::Ticket::Event::OmqArticleAutoResponseEvent;

use strict;
use warnings;

use JSON;
use Encode qw(encode);
use LWP::UserAgent;

our @ObjectDependencies = (
    'Kernel::System::OMQ::AutoResponder::Util',
    'Kernel::System::Ticket'
);

=head1 NAME

Kernel::System::Ticket::Event::OmqArticleAutoResponseEvent - Event handler for article auto response

=head1 SYNOPSIS

Called when auto response has been sent.

=cut

=over

=item new()

Constructor
Creates an Object. Used by OTRS Event System

=cut

sub new {
    my ( $Type ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item Run()

Runs after auto response has been sent.
Sets ticket state to 'closed successful'. Logs action to syslog.

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    # check needed stuff
    for my $Parameter (qw(Data Event UserID)) {
        if ( !$Param{$Parameter} ) {
            $OmqUtil->Log(
                Priority => 'error',
                Message  => "Need $Parameter!"
            );
            return;
        }
    }

    # check if Data param has all needed properties
    for my $Parameter (qw(TicketID)) {
        if ( !$Param{Data}->{$Parameter} ) {
            $OmqUtil->Log(
                Priority => 'error',
                Message  => "Need $Parameter in Data!",
            );
            return;
        }
    }

    my $TicketID = $Param{Data}->{TicketID};

    my %TicketStateDefaultData = $OmqUtil->GetDefaultTicketStateData();

    # load ticket, incl dynamic fields
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $TicketID,
        DynamicFields => 1
    );

    # check if ticket has an auto response
    my $FieldName = 'DynamicField_' . Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_STATUS_NAME();
    my $AutoResponderStatus = $Ticket{$FieldName};

    # delete dynamic field value
    $OmqUtil->ResetDynamicFieldValues( TicketID => $TicketID );

    if ( !$AutoResponderStatus || $AutoResponderStatus eq "EMPTY" ) {
        return 1;
    }

    # get user
    my $UserID = $OmqUtil->GetUserID();

    # update ticket state
    $TicketObject->TicketStateSet(
        State              => $TicketStateDefaultData{Name},
        TicketID           => $TicketID,
        UserID             => $UserID,
        SendNoNotification => 0
    );

    # log action for ticket
    $OmqUtil->Log(
        Priority => 'notice',
        Message  => "Ticket $TicketID has been set to pending by OMQ Auto Responder."
    );

    $Self->UpdateTicketWithSubjectAndBody( TicketID => $TicketID );

    return 1;
}

sub UpdateTicketWithSubjectAndBody {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    my %Ticket = $TicketObject->TicketGet( TicketID => $Param{TicketID} );
    my $ApiKey = $OmqUtil->ApikeyForQueueID( QueueID => $Ticket{QueueID} );

    # get array of article ids
    my @Index = $TicketObject->ArticleIndex( TicketID => $Param{TicketID} );

    # return if empty
    return if !@Index;

    # get last article of ticket
    my %Article = $TicketObject->ArticleGet(
        ArticleID => $Index[-1]
    );

    # send body and subject to server
    $OmqUtil->SendRequest(
        Type => "POST",
        Url  => "/api/auto_responders/reply?ticket_id=$Param{TicketID}&source=OTRS",
        Body => {
            "body"    => $Article{Body},
            "subject" => $Article{Subject}
        },
        ApiKey => $ApiKey
    );

    return 1;
}

1;

=back
