# --
# Kernel/System/OMQ/AutoResponder/Util.pm - Util module for the auto responder
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

package Kernel::System::OMQ::AutoResponder::Util;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use Kernel::System::OMQ::AutoResponder::Constants;

use LWP::UserAgent;
use JSON;
use Encode qw(encode);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::DB',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::User'
);

=head1 NAME

Kernel::System::OMQ::AutoResponder::Util - Util module for Auto responder.

=head1 SYNOPSIS

Contains some utilf functions

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

    $Self->{LogIsEnabled} = $Kernel::OM->Get('Kernel::Config')->Get('OMQ::AutoResponder::Settings::EnableDebugLog');

    return $Self;
}

sub GetDefaultUserData {
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $PostmasterUserID = $ConfigObject->Get('PostmasterUserID') || 1;

    return (
        UserFirstname => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DEFAULT_USER_FIRST_NAME(),
        UserLastname  => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DEFAULT_USER_LAST_NAME(),
        UserLogin     => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DEFAULT_USER_LOGIN(),
        UserEmail     => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DEFAULT_USER_EMAIL(),
        ChangeUserID  => $PostmasterUserID
    );
}

sub GetUserID {
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $UserID     = $UserObject->UserLookup(
        UserLogin => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DEFAULT_USER_LOGIN(),
        Silent    => 1
    );

    # set default user
    if ( !$UserID ) {
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
        my $PostmasterUserID = $ConfigObject->Get('PostmasterUserID') || 1;

        $UserID = $PostmasterUserID;
    }

    return $UserID;
}

sub GetDynamicFields {
    return (
        {
            Name  => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_STATUS_NAME(),
            Label => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_STATUS_LABEL(),
            Type  => 'Text'
        },

        {
            Name  => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_NAME(),
            Label => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_LABEL(),
            Type  => 'HTML'
        },

        {
            Name  => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_BEFORE_NAME(),
            Label => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_BEFORE_LABEL(),
            Type  => 'HTML'
        },

        {
            Name  => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_CONTENT_NAME(),
            Label => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_CONTENT_LABEL(),
            Type  => 'HTML'
        },

        {
            Name  => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_AFTER_NAME(),
            Label => Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_AFTER_LABEL(),
            Type  => 'HTML'
        }
    );
}

sub GetDefaultTicketStateData {
    return (
        Name      => Kernel::System::OMQ::AutoResponder::Constants::OMQ_TICKET_STATE_NAME(),
        Comment   => Kernel::System::OMQ::AutoResponder::Constants::OMQ_TICKET_STATE_COMMENT(),
        StateType => Kernel::System::OMQ::AutoResponder::Constants::OMQ_TICKET_STATE_TYPE()
    );
}

sub SendRequest {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $Host   = $ConfigObject->Get('OMQ::AutoResponder::Settings::URL');
    my $ApiKey = $Param{ApiKey};

    if ( !$ApiKey || $ApiKey eq '' ) {
        $ApiKey = $ConfigObject->Get('OMQ::AutoResponder::Settings::Apikey');
    }

    my $UserAgent = LWP::UserAgent->new();

    # ignores invalid ssl certificates
    $UserAgent->ssl_opts( verify_hostname => 0 );

    # load categories
    my $Request = HTTP::Request->new( $Param{Type} => $Host . $Param{Url} );

    # set request header
    $Request->header(
        'Accept'                       => 'application/json',
        'X-Omq-Auto-Responder-Api-Key' => $ApiKey,
        'Content-Type'                 => 'application/json'
    );

    if ( $Param{Body} ) {
        $Request->content( JSON->new()->utf8()->encode( $Param{Body} ) );
    }

    # send request
    my $Response = $UserAgent->request($Request);

    # do nothing if open tickets couldn't be loaded
    if ( !$Response->is_success() ) {
        my $ErrorMessage = "Could not send request to OMQ Backend.\n";
        $ErrorMessage .= "HTTP ERROR Url: " . $Param{Url} . "\n";
        $ErrorMessage .= "HTTP ERROR Code: " . $Response->code() . "\n";
        $ErrorMessage .= "HTTP ERROR Message: " . $Response->message() . "\n";

        if ( $Response->decoded_content() ) {
            $ErrorMessage .= "HTTP ERROR Content: " . $Response->decoded_content() . "\n";
        }

        $Self->Log(
            Priority => 'error',
            Message  => $ErrorMessage
        );

        print "\n$ErrorMessage\n";
        return;
    }

    my $Content = $Response->decoded_content();
    if ( !$Content || $Content eq '' ) {
        return $Content;
    }

    # decode response
    return JSON->new()->utf8()->decode( encode( 'UTF-8', $Content ) );
}

sub ApikeyForQueueID {
    my ( $Self, %Param ) = @_;

    # get auto default responses
    my %AutoResponse = $Self->GetAutoResponseForQueueID(
        QueueID => $Param{QueueID}
    );

    return if !%AutoResponse;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my %ApiKeys      = %{ $ConfigObject->Get('OMQ::AutoResponder::Settings::Apikeys') };

    while ( ( my %Item ) = each %ApiKeys ) {
        my $Key = $Item{ $AutoResponse{ID} };
        return $Key if $Key;
    }

    return $ConfigObject->Get('OMQ::AutoResponder::Settings::Apikey');
}

sub GetAutoResponseForQueueID {
    my ( $Self, %Param ) = @_;

    # get database object
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    # SQL query
    return if !$DBObject->Prepare(
        SQL => "
            SELECT queue_id, auto_response_id
            FROM queue_auto_response
            WHERE queue_id = ?",
        Bind => [
            \$Param{QueueID}
        ],
        Limit => 1
    );

    # fetch the result
    my %Data;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Data{QueueID} = $Row[0];
        $Data{ID}      = $Row[1];
    }

    return %Data;
}

sub ResetDynamicFieldValues {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldObject      = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    # get dynamic fields
    my $TicketDynamicField = $DynamicFieldObject->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => ['Ticket']
    );

    my @FieldsToDelete = (
        Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_NAME(),
        Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_STATUS_NAME(),
        Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_BEFORE_NAME(),
        Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_CONTENT_NAME(),
        Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_AFTER_NAME()
    );

    # look for auto response field
    for my $DynamicFieldConfig ( @{$TicketDynamicField} ) {

        # delete dynamic field values, so ticket won't be processed again.
        if ( grep( /^$DynamicFieldConfig->{Name}$/, @FieldsToDelete ) ) {
            $DynamicFieldValueObject->ValueDelete(
                FieldID  => $DynamicFieldConfig->{ID},
                ObjectID => $Param{TicketID},
                UserID   => $Self->GetUserID()
            );
        }
    }

    return 1;
}

sub Log {
    my ( $Self, %Param ) = @_;

    my $LogObject = $Kernel::OM->Get('Kernel::System::Log');

    if ( $Param{Priority} eq 'notice' && !$Self->{LogIsEnabled} ) {
        return;
    }

    $LogObject->Log(
        Priority => $Param{Priority},
        Message  => $Param{Message}
    );
}
1;

=back
