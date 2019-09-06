# --
# Kernel/System/DynamicField/Driver/HTML.pm - Driver for DynamicField HTML backend
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

package Kernel::System::DynamicField::Driver::HTML;

use strict;
use warnings;

use parent qw(Kernel::System::DynamicField::Driver::BaseText);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::Main',
);

=over

=item new()

Default constructor. Copied from documentation

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # set field behaviors
    $Self->{Behaviors} = {
        'IsACLReducible'               => 0,
        'IsNotificationEventCondition' => 0,
        'IsSortable'                   => 0,
        'IsFiltrable'                  => 0,
        'IsStatsCondition'             => 0,
        'IsCustomerInterfaceCapable'   => 0,
    };

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get the Dynamic Field Backend custom extensions
    my $DynamicFieldDriverExtensions = $ConfigObject->Get('DynamicFields::Extension::Driver::HTML');

    EXTENSION:
    for my $ExtensionKey ( sort keys %{$DynamicFieldDriverExtensions} ) {

        # skip invalid extensions
        next EXTENSION if !IsHashRefWithData( $DynamicFieldDriverExtensions->{$ExtensionKey} );

        # create a extension config shortcut
        my $Extension = $DynamicFieldDriverExtensions->{$ExtensionKey};

        # check if extension has a new module
        if ( $Extension->{Module} ) {

            # check if module can be loaded
            if ( !$Kernel::OM->Get('Kernel::System::Main')->RequireBaseClass( $Extension->{Module} ) ) {
                die "Can't load dynamic fields backend module"
                    . " $Extension->{Module}! $@";
            }
        }

        # check if extension contains more behaviors
        if ( IsHashRefWithData( $Extension->{Behaviors} ) ) {

            %{ $Self->{Behaviors} } = (
                %{ $Self->{Behaviors} },
                %{ $Extension->{Behaviors} }
            );
        }
    }

    return $Self;
}

=item ReadableValueRender()

Prepare passed value to make it "readable".

Since auto respones escape all HTML chars, this function needs to undo
this transformation for the dynamic field value, that is used by the auto response.

Called by DynamicFieldBackend/Autoresponse Template

=cut

sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';

    $Value = $Self->_TextToHtml( Text => $Value );

    my $Title = $Value;

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
    };

    return $Data;
}

=item _TextToHtml()

Convert escaped HTML back into HTML.

=cut

sub _TextToHtml {
    my ( $Self, %Param ) = @_;

    my $HTML = $Param{Text};

    $HTML =~ s/&amp;/&/g;
    $HTML =~ s/&lt;/</g;
    $HTML =~ s/&gt;/>/g;
    $HTML =~ s/&quot;/"/g;
    $HTML =~ s/&nbsp;/ /g;

    return $HTML;
}

1;

=back
