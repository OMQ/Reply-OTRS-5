# --
# Kernel/System/OMQ/AutoResponder/Constants.pm - Module for Constants
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

package Kernel::System::OMQ::AutoResponder::Constants;

use strict;
use warnings;

# constants for auto responder user
use constant OMQ_DEFAULT_USER_FIRST_NAME => 'OMQ';
use constant OMQ_DEFAULT_USER_LAST_NAME  => 'Auto Responder';
use constant OMQ_DEFAULT_USER_LOGIN      => 'omq-auto-response-user';
use constant OMQ_DEFAULT_USER_EMAIL      => 'omq-auto-responder@localhost.de';

# constants for auto responder ticket state
use constant OMQ_TICKET_STATE_NAME    => 'pending omq auto-responder';
use constant OMQ_TICKET_STATE_COMMENT => 'Answered by omq auto responder, waiting for user action';
use constant OMQ_TICKET_STATE_TYPE    => 'pending auto';

# constants for dynamic field values
use constant OMQ_DYNAMIC_FIELD_NAME  => 'OmqAutoResponse';
use constant OMQ_DYNAMIC_FIELD_LABEL => 'OMQ Auto Response';

use constant OMQ_DYNAMIC_FIELD_STATUS_NAME  => 'OmqAutoResponderTicketStatus';
use constant OMQ_DYNAMIC_FIELD_STATUS_LABEL => 'OMQ Auto responder ticket status';

use constant OMQ_DYNAMIC_FIELD_BEFORE_NAME  => 'OmqAutoResponseBefore';
use constant OMQ_DYNAMIC_FIELD_BEFORE_LABEL => 'OMQ Auto Response Before';

use constant OMQ_DYNAMIC_FIELD_CONTENT_NAME  => 'OmqAutoResponseContent';
use constant OMQ_DYNAMIC_FIELD_CONTENT_LABEL => 'OMQ Auto Response Content';

use constant OMQ_DYNAMIC_FIELD_AFTER_NAME  => 'OmqAutoResponseAfter';
use constant OMQ_DYNAMIC_FIELD_AFTER_LABEL => 'OMQ Auto Response After';

1;
