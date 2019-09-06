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

package Kernel::System::OMQ::AutoResponder::Install;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Cache',
    'Kernel::System::Log',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Daemon::SchedulerDB',
    'Kernel::System::OMQ::AutoResponder::Util',
    'Kernel::System::State',
    'Kernel::System::User'
);

=head1 NAME

Kernel::System::OMQ::AutoResponder::Install - Install package for Auto responder.

=head1 SYNOPSIS

Called during installation processs

=cut

=over

=item new()

Constructor

=cut

sub new {
    my ($Type) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item Install()

Run installation. Create all nesseccary items.

=cut

sub Install {
    my ($Self) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');

    $Self->_InstallDynamicFields();
    $Self->_InstallTicketState();
    $Self->_InstallOMQUser();

    $CacheObject->CleanUp(
        Type => 'DynamicField'
    );

    return 1;
}

=item Uninstall()

Run Uninstall. Remove all objects/fields/settings added by OMQ.

=cut

sub Uninstall {
    my ($Self) = @_;

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
    my $DaemonDB    = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB');

    $Self->_UninstallDynamicFields();
    $Self->_UninstallTicketState();
    $Self->_UninstallOMQUser();

    $CacheObject->CleanUp( Type => 'DynamicField' );
    $CacheObject->CleanUp( Type => 'SchedulerDBRecurrentTaskExecute' );

    $DaemonDB->CronTaskCleanup();

    return 1;
}

=item InstallDynamicFields()

Add dynamic field to store auto response.

=cut

sub _InstallDynamicFields {
    my ($Self) = @_;

    my $OmqUtil = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    my @DynamicFields = $OmqUtil->GetDynamicFields();

    for (@DynamicFields) {
        $Self->_AddDynamicField(
            Name  => $_->{Name},
            Label => $_->{Label},
            Type  => $_->{Type}
        );
    }

    return 1;
}

=item _UninstallDynamicFields()

Remove auto response dynamic field incl. data.

=cut

sub _UninstallDynamicFields {
    my ($Self) = @_;

    # get objects
    my $OmqUtil       = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');
    my @DynamicFields = $OmqUtil->GetDynamicFields();

    for (@DynamicFields) {
        $Self->_DeleteDynamicField( Name => $_->{Name} );
    }

    return 1;
}

=item _InstallTicketState()

Add ticket state for tickets answered by the auto responder

=cut

sub _InstallTicketState {
    my ($Self) = @_;

    my $StateObject = $Kernel::OM->Get('Kernel::System::State');
    my $OmqUtil     = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    my %DefaultData = $OmqUtil->GetDefaultTicketStateData();

    # get ticket state ID
    my $StateID = $Self->_TicketStateLookUp(
        State => $DefaultData{Name},
    );

    # Look up state type
    my $StateType = $StateObject->StateTypeLookup(
        StateType => $DefaultData{StateType}
    );

    # check if state exists
    if ($StateID) {

        # state can't be deleted, if it exists,
        # make it valid again
        $StateObject->StateUpdate(
            ID      => $StateID,
            Name    => $DefaultData{Name},
            ValidID => 1,
            TypeID  => $StateType,
            UserID  => 1
        );

        return;
    }

    $StateObject->StateAdd(
        Name    => $DefaultData{Name},
        Comment => $DefaultData{Comment},
        ValidID => 1,
        TypeID  => $StateType,
        UserID  => 1,
    );

    return 1;
}

=item _UninstallTicketState()

Remove ticket state for tickets answered by the auto responder

=cut

sub _UninstallTicketState {
    my ($Self) = @_;

    my $StateObject = $Kernel::OM->Get('Kernel::System::State');
    my $OmqUtil     = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    my %DefaultData = $OmqUtil->GetDefaultTicketStateData();

    # get ticket state ID
    my $StateID = $Self->_TicketStateLookUp(
        State => $DefaultData{Name},
    );

    # check if state exists
    if ( !$StateID ) {
        return;
    }

    # Look up state type
    my $StateType = $StateObject->StateTypeLookup(
        StateType => $DefaultData{StateType}
    );

    # state can't be deleted
    # make it invalid
    $StateObject->StateUpdate(
        ID      => $StateID,
        Name    => $DefaultData{Name},
        ValidID => 2,
        TypeID  => $StateType,
        UserID  => 1
    );

    return 1;
}

=item _TicketStateLookUp()

Lookup ticket state by passed state name.
Copied from Kernel::System::State->StateLookup()
Use custom state lookup, because default lookup prints error
if nothing was found.

=cut

sub _TicketStateLookUp {
    my ( $Self, %Param ) = @_;

    my $StateObject = $Kernel::OM->Get('Kernel::System::State');

    my %StateList = $StateObject->StateList(
        Valid  => 0,
        UserID => 1,
    );

    my %StateListReverse = reverse %StateList;
    return $StateListReverse{ $Param{State} };
}

=item _InstallOMQUser()

Create User that owns all tickets answered by OMQ auto responder.

=cut

sub _InstallOMQUser {

    #my ( $Self, %Param ) = @_;

    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $OmqUtil    = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    my %DefaultData = $OmqUtil->GetDefaultUserData();

    # check if user already exists
    my $UserID = $UserObject->UserLookup(
        UserLogin => $DefaultData{UserLogin},
        Silent    => 1
    );

    # make user valid
    if ($UserID) {
        $UserObject->UserUpdate(
            UserID  => $UserID,
            ValidID => 1,
            %DefaultData
        );

        return;
    }

    # create user
    $UserObject->UserAdd(
        ValidID => 1,
        %DefaultData
    );

    return 1;
}

=item _InstallOMQUser()

Remove OMQ User.

=cut

sub _UninstallOMQUser {

    #my ( $Self, %Param ) = @_;

    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
    my $OmqUtil    = $Kernel::OM->Get('Kernel::System::OMQ::AutoResponder::Util');

    my %DefaultData = $OmqUtil->GetDefaultUserData();

    # get user
    my $UserID = $UserObject->UserLookup(
        UserLogin => $DefaultData{UserLogin},
        Silent    => 1
    );

    return if !$UserID;

    # users can not be deleted
    # make invalid
    $UserObject->UserUpdate(
        UserID  => $UserID,
        ValidID => 2,
        %DefaultData
    );

    return 1;
}

sub _AddDynamicField {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    my $FieldName  = $Param{Name};
    my $FieldLabel = $Param{Label};
    my $FieldType  = $Param{Type};

    # get dynamic field
    my $DynamicField = $DynamicFieldObject->DynamicFieldGet(
        Name => $FieldName,
    );

    # check if dynamic field exists
    if ( !IsHashRefWithData($DynamicField) ) {
        $DynamicFieldObject->DynamicFieldAdd(
            Name          => $FieldName,
            Label         => $FieldLabel,
            FieldOrder    => 1,
            FieldType     => $FieldType,
            ObjectType    => 'Ticket',
            ValidID       => 1,
            InternalField => 1,
            UserID        => 1,
            Config        => {}
        );
    }

    return 1;
}

sub _DeleteDynamicField {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldObject  = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackend = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # get dynamic field
    my $DynamicField = $DynamicFieldObject->DynamicFieldGet(
        Name => $Param{Name},
    );

    # check if dynamic field exists
    if ( IsHashRefWithData($DynamicField) ) {

        # delete all values for dynamic field
        my $ValuesDeleteSuccess = $DynamicFieldBackend->AllValuesDelete(
            DynamicFieldConfig => $DynamicField,
            UserID             => 1,
        );

        # delete dynamic field
        if ($ValuesDeleteSuccess) {
            $DynamicFieldObject->DynamicFieldDelete(
                ID     => $DynamicField->{ID},
                UserID => 1,
            );
        }
    }

    return 1;
}

1;

=back
