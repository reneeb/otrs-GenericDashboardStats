# --
# Copyright (C) 2001-2021 OTRS AG, https://otrs.com/
# Copyright (C) 2021-2022 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::Dashboard::TicketStatsGeneric;

use strict;
use warnings;

use Kernel::System::DateTime qw(:all);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if !$Self->{$Needed};
    }

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    return;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },

        # Don't cache this globally as it contains JS that is not inside of the HTML.
        CacheTTL => undef,
        CacheKey => undef,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $Key      = $LayoutObject->{UserLanguage} . '-' . $Self->{Name};
    my $CacheKey = 'TicketStats' . '-' . $Self->{UserID} . '-' . $Key;

# ---
# PS
# ---
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');

    my $ConfigKey = $Self->{Config}->{SysConfigBase} || 'GenericDashboardStats';

    if ( $Self->{Name} eq '0250-TicketStats' ) {
        $ConfigKey = $Self->{Name};
    }

    $CacheKey = 'TicketStats' . '-' . $Self->{UserID} . '-' . $Key . '-' . $ConfigKey;
# ---

    my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => 'Dashboard',
        Key  => $CacheKey,
    );

    if ( ref $Cache ) {

        # send data to JS
        $LayoutObject->AddJSData(
# ---
# PS
# ---
#            Key   => 'DashboardTicketStats',
            Key   => 'GenericTicketStats-' . $Cache->{Key},
# ---
            Value => $Cache,
        );

        return $LayoutObject->Output(
            TemplateFile => 'AgentDashboardTicketStats',
            Data         => $Cache,
            AJAX         => $Param{AJAX},
        );
    }

    my %Axis = (
        '7Day' => {
            0 => 'Sun',
            1 => 'Mon',
            2 => 'Tue',
            3 => 'Wed',
            4 => 'Thu',
            5 => 'Fri',
            6 => 'Sat',
        },
    );

    my $ClosedText     = $LayoutObject->{LanguageObject}->Translate('Closed');
    my $CreatedText    = $LayoutObject->{LanguageObject}->Translate('Created');
    my $StateText      = $LayoutObject->{LanguageObject}->Translate('State');
    my @TicketsCreated = ();
    my @TicketsClosed  = ();
    my @TicketWeekdays = ();
    my $Max            = 0;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $TimeZone = $Self->{UserTimeZone} || OTRSTimeZoneGet();

# ---
# PS
# ---
    my @DefaultColors = (
        '#EC9073', '#6BAD54', '#E2F626', '#0F22E4', '#1FE362', '#C5F566', '#8D23A8', '#78A7FC',
        '#DFC01B', '#43B261', '#53758D', '#C1AE45', '#6CD13D', '#E0CA0E', '#652188', '#3EBB34',
        '#8F53EA', '#956669', '#34A0FB', '#F50178', '#AB766A', '#BEA029', '#ABE124', '#A68477',
    );

    my @ShownStats;
    my %StatIndexes;
    my @Colors;

    my %Stats     = %{ $ConfigObject->Get( $ConfigKey . '::Stats' ) || {} };
    my %UserStats = %Stats;

    GENERICSTAT:
    for my $Stat ( sort keys %Stats ) {

        # check permissions
        if ( $Stats{$Stat}->{group} ) {
            my $PermissionOK = 0;
            my @Groups       = split /;/, $Stats{$Stat}->{group};

            STATGROUP:
            for my $Group (@Groups) {
                my $HasPermission = $GroupObject->PermissionCheck(
                    UserID    => $Self->{UserID},
                    GroupName => $Group,
                    Type      => 'ro',
                );

                if ($HasPermission) {
                    $PermissionOK = 1;
                    last STATGROUP;
                }
            }

            if ( !$PermissionOK ) {
                delete $UserStats{$Stat};
                next GENERICSTAT;
            }
        }

        my $Key         = $Stats{$Stat}->{OptionKey};
        my $StatsConfig = $ConfigObject->Get( $Key ) || {};

        $Stats{$Stat}->{SearchOptions} = $StatsConfig;

        my $Label = $Stats{$Stat}->{label} || $Stat;
        $Stats{$Stat}->{label} = $LayoutObject->{LanguageObject}->Translate( $Label );

        push @Colors, $Stats{$Stat}->{color} // shift @DefaultColors;

        push @ShownStats, [ $Stats{$Stat}->{label} ];
        $StatIndexes{$Stat} = $#ShownStats;
    }

    my $Days = $ConfigObject->Get( $ConfigKey . '::Days') || 7;

#    for my $DaysBack ( 0 .. 6 ) {
    for my $DaysBack ( 0 .. $Days-1 ) {
# ---

        # cache results for 30 min. for todays stats
        my $CacheTTL = 60 * 30;

        my $DateTimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                TimeZone => $TimeZone,
            }
        );
        if ($DaysBack) {
            $DateTimeObject->Subtract( Days => $DaysBack );

            # for past 6 days cache results for 8 days (should not change)
            $CacheTTL = 60 * 60 * 24 * 8;
        }
        $DateTimeObject->ToOTRSTimeZone();

        my $DateTimeValues = $DateTimeObject->Get();
        my $WeekDay        = $DateTimeValues->{DayOfWeek} == 7 ? 0 : $DateTimeValues->{DayOfWeek};

# ---
# PS
# ---
        my $Tick = $Self->{Config}->{UseDate} ?
            $DateTimeObject->Format( Format => $Self->{Config}->{DateFormat} || '%Y-%m-%d' ) :
            $LayoutObject->{LanguageObject}->Translate( $Axis{'7Day'}->{$WeekDay} );
# ---
        unshift(
            @TicketWeekdays,
# ---
# PS
# ---
#            $LayoutObject->{LanguageObject}->Translate( $Axis{'7Day'}->{$WeekDay} )
            $Tick
# ---
        );

        my $TimeStart = $DateTimeObject->Format( Format => '%Y-%m-%d 00:00:00' );
        my $TimeStop  = $DateTimeObject->Format( Format => '%Y-%m-%d 23:59:59' );
# ---
# PS
# ---

        USERSTAT:
        for my $Stat ( sort keys %UserStats ) {
            my $Type = $Stats{$Stat}->{type};

            my $Count;
            if ( $Type eq 'plugin' ) {
                my $Plugin = $Kernel::OM->Get( $Stats{$Stat}->{module} );
                next USERSTAT if !$Plugin;

                my %Options = (
                    'TimeNewerDate' => $TimeStart,
                    'TimeOlderDate' => $TimeStop,
                    SearchOptions   => $Stats{$Stat}->{SearchOptions},
                    Config          => $Self->{Config},
                    Stat            => $Stat,
                    GraphConfig     => $Stats{$Stat},
                );

                $Count = $Plugin->Run( %Options );
            }
            else {
                my %Options = (
                    $Type . 'TimeNewerDate' => $TimeStart,
                    $Type . 'TimeOlderDate' => $TimeStop,
                    %{ $Stats{$Stat}->{SearchOptions} },
                );

                $Count = $TicketObject->TicketSearch(
                    %Options,

                    # cache search result 30 min
                    CacheTTL => 60 * 30,
                    CacheTTL => 0,

                    CustomerID => $Param{Data}->{UserCustomerID},
                    Result     => 'COUNT',

                    # search with user permissions
                    Permission => $Self->{Config}->{Permission} || 'ro',
                    UserID => $Self->{UserID},
                );
            }

            if ( $Count && $Count > $Max ) {
                $Max = $Count;
            }

            my $Index = $StatIndexes{$Stat};
            splice @{ $ShownStats[$Index] }, 1, 0,$Count;
        }

        if ( $Self->{Name} eq '0250-TicketStats' ) {
# ---

        my $CountCreated = $TicketObject->TicketSearch(

            # cache search result
            CacheTTL => $CacheTTL,

            # tickets with create time after ... (ticket newer than this date) (optional)
            TicketCreateTimeNewerDate => $TimeStart,

            # tickets with created time before ... (ticket older than this date) (optional)
            TicketCreateTimeOlderDate => $TimeStop,

            CustomerID => $Param{Data}->{UserCustomerID},
            Result     => 'COUNT',

            # search with user permissions
            Permission => $Self->{Config}->{Permission} || 'ro',
            UserID     => $Self->{UserID},
        ) || 0;
        if ( $CountCreated && $CountCreated > $Max ) {
            $Max = $CountCreated;
        }
        push @TicketsCreated, $CountCreated;

        my $CountClosed = $TicketObject->TicketSearch(

            # cache search result
            CacheTTL => $CacheTTL,

            # tickets with create time after ... (ticket newer than this date) (optional)
            TicketCloseTimeNewerDate => $TimeStart,

            # tickets with created time before ... (ticket older than this date) (optional)
            TicketCloseTimeOlderDate => $TimeStop,

            CustomerID => $Param{Data}->{UserCustomerID},
            Result     => 'COUNT',

            # search with user permissions
            Permission => $Self->{Config}->{Permission} || 'ro',
            UserID     => $Self->{UserID},
        ) || 0;
        if ( $CountClosed && $CountClosed > $Max ) {
            $Max = $CountClosed;
        }
        push @TicketsClosed, $CountClosed;
# ---
# PS
# ---
        @ShownStats = (
            [ $CreatedText, reverse @TicketsCreated ],
            [ $ClosedText,  reverse @TicketsClosed ],
        );
        }
# ---
    }

    unshift(
        @TicketWeekdays,
        $StateText
    );

    my @ChartData = (
# ---
# PS
# ---
#        $LayoutObject->{LanguageObject}->Translate('7 Day Stats'),
        $LayoutObject->{LanguageObject}->Translate(
            $ConfigObject->Get( $ConfigKey . '::Title')
        ),
# ---
        \@TicketWeekdays,
# ---
# PS
# ---
#        [ $CreatedText, reverse @TicketsCreated ],
#        [ $ClosedText,  reverse @TicketsClosed ],
        @ShownStats,
# ---
    );

# ---
# PS
# ---
    @Colors = @DefaultColors if !@Colors;
# ---

    my %Data = (
        %{ $Self->{Config} },
# ---
# PS
# ---
        Colors => \@Colors,
        Ticks  => [1..$Days],
        ReduceXTicks => $Self->{Config}->{ReduceXTicks} || 0,
        Area         => ( $Self->{Config}->{Area} eq 'false' ? 'false' : 'true' ),
# ---
        Key       => int rand 99999,
        ChartData => \@ChartData,
    );

    if ( $Self->{Config}->{CacheTTLLocal} ) {
        $Kernel::OM->Get('Kernel::System::Cache')->Set(
            Type  => 'Dashboard',
            Key   => $CacheKey,
            Value => \%Data,
            TTL   => $Self->{Config}->{CacheTTLLocal} * 60,
        );
    }

    # send data to JS
    $LayoutObject->AddJSData(
# ---
# PS
# ---
#        Key   => 'DashboardTicketStats',
        Key   => 'GenericTicketStats-' . $Data{Key},
# ---
        Value => \%Data
    );

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardTicketStats',
        Data         => \%Data,
        AJAX         => $Param{AJAX},
    );

    return $Content;
}

1;

