# --
# Kernel/System/Ticket/Event/OmqArticleCreatedEvent.pm - Event handler to load auto response after article create
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

package Kernel::System::Ticket::Event::OmqArticleCreatedEvent;

use strict;
use warnings;

use JSON;
use Encode qw(encode);
use LWP::UserAgent;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Ticket',
    'Kernel::System::AutoResponse',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::PostMaster::LoopProtection',
    'Kernel::System::OMQ::AutoResponder::Util'
);

=head1 NAME

Kernel::System::Ticket::Event::OmqArticleCreatedEvent - Event handler for article create

=head1 SYNOPSIS

Called when article has been created.

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

=item run()

Get created article, check if its suitable for autoresponse.
Analyze article body with auto response API, and save response
in dynamic field.

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $OmqUtil = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    # check needed stuff
    for my $Parameter (qw(Data Event Config UserID)) {
        if ( !$Param{$Parameter} ) {
            $OmqUtil->Log(
                Priority => 'error',
                Message  => "Need $Parameter!"
            );
            return;
        }
    }

    # check if Data param has all needed properties
    for my $Parameter (qw(TicketID ArticleID)) {
        if ( !$Param{Data}->{$Parameter} ) {
            $OmqUtil->Log(
                Priority => 'error',
                Message  => "Need $Parameter in Data!",
            );
            return;
        }
    }

    # check if article matches auto response conditions
    my %Article = $Self->_CheckParams(%Param);
    return if !%Article;

    my $TemplateType = $Self->_CheckTemplateType( QueueID => $Article{QueueID} );

    # analyze article body (customer request)
    my %AnalyzeResponse = $Self->_AnalyzeCustomerRequest(
        ArticleText    => $Article{Body},
        ArticleSubject => $Article{Subject},
        TicketID       => $Param{Data}->{TicketID},
        QueueID        => $Article{QueueID}
    );

    return if ( $AnalyzeResponse{Error} != 0 );

    my $AutoResponse           = $AnalyzeResponse{Answer};
    my $AutoResponseRangeCount = $AnalyzeResponse{RangeCount};

    # save autoresponse
    $Self->_SaveOmqAutoResponse(
        Answer         => $AutoResponse,
        TicketID       => $Param{Data}->{TicketID},
        IsJsonAnswer   => $AnalyzeResponse{IsJsonAnswer},
        IsJsonTemplate => $TemplateType eq 'JSON'
    );

    $Self->_UpdateAutoResponseTicketStatus(
        RangeCount => $AutoResponseRangeCount,
        TicketID   => $Param{Data}->{TicketID}
    );

    return 1;
}

=item _CheckParams()

Check if the Event/Article is valid for
omq auto response.

Returns article, if auto response should be used.

=cut

sub _CheckParams {
    my ( $Self, %Param ) = @_;

    # ignore all other events
    return if $Param{Event} ne 'ArticleCreate';

    # load article via ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my %Article      = $TicketObject->ArticleGet(
        TicketID  => $Param{Data}->{TicketID},
        ArticleID => $Param{Data}->{ArticleID}
    );

    # do not search if article is not created by customer
    return if $Article{SenderType} ne 'customer';

    # Only handle first articles, (so follow up emails etc. won't be handled)
    my @ArticleIndex = $TicketObject->ArticleIndex( TicketID => $Param{Data}->{TicketID} );
    my $FirstArticleID = $ArticleIndex[0];
    return if $FirstArticleID ne $Param{Data}->{ArticleID};

    # do not search if sender is ignored by config
    my $NoAutoRegExp = $Kernel::OM->Get('Kernel::Config')->Get('SendNoAutoResponseRegExp');
    return if ( $Article{From} =~ /$NoAutoRegExp/i );

    # check for loop protection
    my $LoopProtectionObject = $Kernel::OM->Get('Kernel::System::PostMaster::LoopProtection');
    return if ( !$LoopProtectionObject->Check( To => $Article{From} ) );

    # get auto default responses
    my %AutoResponse = $Kernel::OM->Get('Kernel::System::AutoResponse')->AutoResponseGetByTypeQueueID(
        QueueID => $Article{QueueID},
        Type    => 'auto reply',
    );

    # check of auto response has dynamic field entry
    return if ( !%AutoResponse || !( $AutoResponse{Text} =~ /OmqAutoResponse/ ) );

    my $ArticleType = $Article{ArticleType};

    # if article is phone
    if ( $ArticleType eq 'phone' ) {

        # no nothing if no auto response is sent for phone or web request tickets
        if ( $Kernel::OM->Get('Kernel::Config')->Get('AutoResponseForWebTickets') ) {
            $Self->_StoreDefaultReply(
                QueueID        => $Article{QueueID},
                TicketID       => $Param{Data}->{TicketID},
                ArticleText    => $Article{Body},
                ArticleSubject => $Article{Subject},
            );
        }
        return;
    }

    # only search for email-external or webrequests.
    if ( $ArticleType eq 'email-external' || $ArticleType eq 'webrequest' ) {
        return %Article;
    }

    return;
}

=item _AnalyzeCustomerRequest()

Analyzes the passed text by sending it to the auto responder API.

=cut

sub _AnalyzeCustomerRequest {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    # get api settings
    my $Host   = $ConfigObject->Get('OMQ::AutoResponder::Settings::URL');
    my $ApiKey = $OmqUtil->ApikeyForQueueID( QueueID => $Param{QueueID} );
    my $Url    = "$Host/api/auto_responders/search";

    # add params
    $Url .= "?ticket_id=$Param{TicketID}&source=OTRS&external_categories=$Param{QueueID}";

    return (
        Answer     => '',
        RangeCount => 0,
        Error      => 1
    ) if !$ApiKey;

    # set custom HTTP request header fields
    my $Request = HTTP::Request->new( POST => $Url );

    $Request->header(
        'X-Omq-Auto-Responder-Api-Key' => $ApiKey,
        'Content-Type'                 => 'application/json; charset=utf-8'
    );

    my $Body = JSON->new()->utf8()->encode(
        {
            "body"    => $Param{ArticleText},
            "subject" => $Param{ArticleSubject}
        }
    );

    $Request->content($Body);

    # create user agent
    my $UserAgent = LWP::UserAgent->new();

    # perform request
    my $Response = $UserAgent->request($Request);

    # log result
    if ( $Response->is_success() ) {

        if ( $Response->header('Content-Type') =~ /text\/html/ ) {

            # handle and clear response
            my $HtmlAnswer = $Response->decoded_content();
            $HtmlAnswer =~ s/[\n\r\t]+//g;

            return (
                Answer       => $HtmlAnswer,
                RangeCount   => $Response->header('X-Omq-Content-Range'),
                Error        => 0,
                IsJsonAnswer => 0
            );

        }
        else {
            my $JsonAnswer = JSON->new()->utf8()->decode( $Response->content() );

            return (
                Answer       => $JsonAnswer,
                RangeCount   => $Response->header('X-Omq-Content-Range'),
                Error        => 0,
                IsJsonAnswer => 1
            );
        }
    }
    else {
        # create error message and log
        my $ErrorMessage = "Could not search for auto response answers.\n";
        $ErrorMessage .= "HTTP ERROR Code: " . $Response->code() . "\n";
        $ErrorMessage .= "HTTP ERROR Message: " . $Response->message() . "\n";
        $ErrorMessage .= "HTTP ERROR Content: " . $Response->decoded_content() . "\n";

        $OmqUtil->Log(
            Priority => 'error',
            Message  => $ErrorMessage
        );

        return (
            Answer     => '',
            RangeCount => 0,
            Error      => 1
        );
    }
}

=item _SaveOmqAutoResponse()

Saves the passed text to the passed dynamic field.

    $Self->_SaveOmqAutoResponse(
        Text => 'Text to store',
        TicketID => 12345,
        FieldName => 'OmqAutoResponse'
    );

=cut

sub _SaveOmqAutoResponse {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldObject      = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');
    my $OmqUtil                 = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    # get user
    my $UserID = $OmqUtil->GetUserID();

    # get dynamic fields
    my $TicketDynamicField = $DynamicFieldObject->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => ['Ticket']
    );

    my $AutoResponseFieldId;
    my $AutoResponseBeforeFieldId;
    my $AutoResponseContentFieldId;
    my $AutoResponseAfterFieldId;

    # look for auto response field
    for my $DynamicFieldConfig ( @{$TicketDynamicField} ) {
        if ( $DynamicFieldConfig->{Name} eq Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_NAME() ) {
            $AutoResponseFieldId = $DynamicFieldConfig->{ID}
        }

        if (
            $DynamicFieldConfig->{Name} eq
            Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_BEFORE_NAME()
            )
        {
            $AutoResponseBeforeFieldId = $DynamicFieldConfig->{ID}
        }

        if (
            $DynamicFieldConfig->{Name} eq
            Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_CONTENT_NAME()
            )
        {
            $AutoResponseContentFieldId = $DynamicFieldConfig->{ID}
        }

        if (
            $DynamicFieldConfig->{Name} eq
            Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_AFTER_NAME()
            )
        {
            $AutoResponseAfterFieldId = $DynamicFieldConfig->{ID}
        }
    }

    my $Answer = $Param{Answer};

    # if template has 3 placeholders (greeting, content, footer)
    if ( $Param{IsJsonTemplate} ) {

        my $AnswerBefore;
        my $AnswerContent;
        my $AnswerAfter;

        # if answer is returned in json format
        if ( $Param{IsJsonAnswer} ) {

            # read json content
            $AnswerBefore  = $Answer->{before};
            $AnswerContent = $Answer->{content};
            $AnswerAfter   = $Answer->{after};
        }
        else {
            # otherwise store whole html content in answer content field
            $AnswerBefore  = "";
            $AnswerContent = $Answer;
            $AnswerAfter   = "";
        }

        # store dynamic value
        $DynamicFieldValueObject->ValueSet(
            FieldID  => $AutoResponseBeforeFieldId,
            ObjectID => $Param{TicketID},
            Value    => [ { ValueText => $AnswerBefore } ],
            UserID   => $UserID
        );

        # store dynamic value
        $DynamicFieldValueObject->ValueSet(
            FieldID  => $AutoResponseContentFieldId,
            ObjectID => $Param{TicketID},
            Value    => [ { ValueText => $AnswerContent } ],
            UserID   => $UserID
        );

        # store dynamic value
        $DynamicFieldValueObject->ValueSet(
            FieldID  => $AutoResponseAfterFieldId,
            ObjectID => $Param{TicketID},
            Value    => [ { ValueText => $AnswerAfter } ],
            UserID   => $UserID
        );
    }
    else {
        # if template has single placeholder (legacy support)

        my $AnswerHTML;

        # if json result is returned, combine html fragments
        if ( $Param{IsJsonAnswer} ) {
            $AnswerHTML = "";

            $AnswerHTML = $Answer->{before} if $Answer->{before};
            $AnswerHTML .= $Answer->{content} if $Answer->{content};
            $AnswerHTML .= $Answer->{after}   if $Answer->{after};

            # if html is returned, simply store whole html in field
        }
        else {
            $AnswerHTML = $Answer;
        }

        # store dynamic value
        $DynamicFieldValueObject->ValueSet(
            FieldID  => $AutoResponseFieldId,
            ObjectID => $Param{TicketID},
            Value    => [ { ValueText => $AnswerHTML } ],
            UserID   => $UserID
        );

    }

    return 1;
}

=item _StoreDefaultReply()

Load default reply in case of non searchable ticket with auto response.

=cut

sub _StoreDefaultReply {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $OmqUtil      = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    # get api settings
    my $Host   = $ConfigObject->Get('OMQ::AutoResponder::Settings::URL');
    my $ApiKey = $OmqUtil->ApikeyForQueueID( QueueID => $Param{QueueID} );
    my $Url    = "$Host/api/auto_responders/empty_reply?source=OTRS";

    return if !$ApiKey;

    # set custom HTTP request header fields
    my $Request = HTTP::Request->new( POST => $Url );

    $Request->header(
        'X-Omq-Auto-Responder-Api-Key' => $ApiKey,
        'Content-Type'                 => 'application/json; charset=utf-8'
    );

    # always send empty body
    $Request->content(
        JSON->new()->utf8()->encode(
            {
                "body"    => $Param{ArticleText},
                "subject" => $Param{ArticleSubject}
            }
            )
    );

    # create user agent
    my $UserAgent = LWP::UserAgent->new();

    # perform request
    my $Response = $UserAgent->request($Request);

    my $Answer;
    my $IsJsonAnswer;
    my $TemplateType = $Self->_CheckTemplateType( QueueID => $Param{QueueID} );

    # log result
    if ( $Response->is_success() ) {
        if ( $Response->header('Content-Type') =~ /text\/html/ ) {

            # handle and clear response
            $Answer = $Response->decoded_content();
            $Answer =~ s/[\n\r\t]+//g;

            $IsJsonAnswer = 0;
        }
        else {
            $Answer       = JSON->new()->utf8()->decode( $Response->content() );
            $IsJsonAnswer = 1;
        }
    }
    else {
        # create error message and log
        my $ErrorMessage = "Could not load empty reply for auto responder.\n";
        $ErrorMessage .= "HTTP ERROR Code: " . $Response->code() . "\n";
        $ErrorMessage .= "HTTP ERROR Message: " . $Response->message() . "\n";
        $ErrorMessage .= "HTTP ERROR Content: " . $Response->decoded_content() . "\n";

        $OmqUtil->Log(
            Priority => 'error',
            Message  => $ErrorMessage
        );

        return;
    }

    # save autoresponse
    $Self->_SaveOmqAutoResponse(
        Answer         => $Answer,
        TicketID       => $Param{TicketID},
        IsJsonAnswer   => $IsJsonAnswer,
        IsJsonTemplate => $TemplateType eq 'JSON'
    );
}

=item _UpdateAutoResponseTicketStatus()

Update the auto responder status for ticket.
Can be "EMPTY" or "ACTIVE"

=cut

sub _UpdateAutoResponseTicketStatus {
    my ( $Self, %Param ) = @_;

    my $OmqUtil   = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    # get user
    my $UserID = $OmqUtil->GetUserID();

    if ( $Param{RangeCount} != 0 ) {

        # update ticket owner
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
        $TicketObject->TicketOwnerSet(
            TicketID           => $Param{TicketID},
            NewUserID          => $UserID,
            UserID             => $UserID,
            SendNoNotification => 1
        );
    }

    my $DynamicFieldId;
    my $DynamicFieldObject      = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    # get dynamic fields
    my $TicketDynamicField = $DynamicFieldObject->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => ['Ticket']
    );

    # look for auto response field
    for my $DynamicFieldConfig ( @{$TicketDynamicField} ) {
        if (
            $DynamicFieldConfig->{Name} eq
            Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_STATUS_NAME()
            )
        {
            $DynamicFieldId = $DynamicFieldConfig->{ID}
        }
    }

    # check if field exists
    if ( !$DynamicFieldId ) {
        $OmqUtil->Log(
            Priority => 'error',
            Message =>
                "Could not find dynamic field for name ${Kernel::System::OMQ::AutoResponder::Constants::OMQ_DYNAMIC_FIELD_STATUS_NAME()}"
        );

        return;
    }

    my $Status = $Param{RangeCount} == 0 ? 'EMPTY' : 'ACTIVE';

    # store dynamic value
    $DynamicFieldValueObject->ValueSet(
        FieldID  => $DynamicFieldId,
        ObjectID => $Param{TicketID},
        Value    => [ { ValueText => $Status } ],
        UserID   => $UserID
    );

    return 1;
}

=item _CheckTemplateType()

Return type of template, depending on placeholders

=cut

sub _CheckTemplateType {
    my ( $Self, %Param ) = @_;

    my $AutoResponseObject = $Kernel::OM->Get('Kernel::System::AutoResponse');

    # get auto default responses
    my %AutoResponse = $AutoResponseObject->AutoResponseGetByTypeQueueID(
        QueueID => $Param{QueueID},
        Type    => 'auto reply',
    );

    if ( $AutoResponse{Text} =~ /OmqAutoResponseContent/ ) {
        return 'JSON'
    }

    return 'HTML';
}

1;

=back
