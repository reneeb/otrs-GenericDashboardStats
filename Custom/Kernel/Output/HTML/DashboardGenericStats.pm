# --
# Kernel/Output/HTML/DashboardGenericStats.pm
# Copyright (C) 2001-2014 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::DashboardGenericStats;

use strict;
use warnings;

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

# ---
# PS
# ---
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
# ---

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $Key      = $LayoutObject->{UserLanguage} . '-' . $Self->{Name};
    my $CacheKey = 'TicketStats' . '-' . $Self->{UserID} . '-' . $Key;

    my $Cache = $Self->{CacheObject}->Get(
        Type => 'Dashboard',
        Key  => $CacheKey,
    );

    if ( ref $Cache ) {
        return $LayoutObject->Output(
            TemplateFile   => 'AgentDashboardTicketStats',
            Data           => $Cache,
            KeepScriptTags => $Param{AJAX},
        );
    }

# ---
# PS
# ---
    my $Days = $ConfigObject->Get('GenericDashboardStats::Days') || 14;
# ---

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

    my @TicketsCreated = ();
    my @TicketsClosed  = ();
    my @TicketWeekdays = ();
    my @TicketYAxis    = ();
    my $Max            = 0;

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

# ---
# PS
# ---
    my %Stats = %{ $ConfigObject->Get( 'GenericDashboardStats::Stats' ) || {} };

    for my $Stat ( keys %Stats ) {
        my $Key         = $Stats{$Stat}->{OptionKey};
        my $StatsConfig = $Self->{ConfigObject}->Get( $Key ) || {};

        $Stats{$Stat}->{SearchOptions} = $StatsConfig;

        my $Label = $Stats{$Stat}->{label} || $Stat;
        $Stats{$Stat}->{label} = $Self->{LayoutObject}->{LanguageObject}->Get( $Label );
    }

#    for my $Key ( 0 .. 6 ) {
    for my $Key ( 0 .. $Days-1 ) {
# ---

        my $TimeNow = $Self->{TimeObject}->SystemTime();
        if ($Key) {
            $TimeNow = $TimeNow - ( 60 * 60 * 24 * $Key );
        }
        my ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay )
            = $Self->{TimeObject}->SystemTime2Date(
            SystemTime => $TimeNow,
            );

        unshift(
            @TicketWeekdays,

# ---
# PS
# ---
#            [
#                6 - $Key,
#                $LayoutObject->{LanguageObject}->Translate( $Axis{'7Day'}->{$WeekDay} )
#            ]
            [ ($Days-1) - $Key, $LayoutObject->{LanguageObject}->Get( $Axis{'7Day'}->{$WeekDay} ) ]
# ---
        );

# ---
# PS
# ---
        for my $Stat ( keys %Stats ) {
            my %Options = (
                $Stats{$Stat}->{type} . 'TimeNewerDate' => "$Year-$Month-$Day 00:00:00",
                $Stats{$Stat}->{type} . 'TimeOlderDate' => "$Year-$Month-$Day 23:59:59",

		        %{ $Stats{$Stat}->{SearchOptions} },
            );

            my $CountCreated = $Self->{TicketObject}->TicketSearch(
                %Options,

                # cache search result 30 min
                CacheTTL => 60 * 30,

                CustomerID => $Param{Data}->{UserCustomerID},
                Result     => 'COUNT',

                # search with user permissions
                Permission => $Self->{Config}->{Permission} || 'ro',
                UserID => $Self->{UserID},
            );

            if ( $CountCreated && $CountCreated > $Max ) {
                $Max = $CountCreated;
            }

            push @{ $Stats{$Stat}->{data} }, [ ($Days-1) - $Key, $CountCreated ];
        }
    }

    # calculate the maximum height and the tick steps of y axis
    if ( $Max <= 10 ) {
        for ( my $i = 0; $i <= 10; $i += 2 ) {
            push @TicketYAxis, $i
        }
    }
    elsif ( $Max <= 20 ) {
        for ( my $i = 0; $i <= 20; $i += 4 ) {
            push @TicketYAxis, $i
        }
    }
    elsif ( $Max <= 100 ) {
        for ( my $i = 0; $i <= ( ( ( $Max - $Max % 10 ) / 10 ) + 1 ) * 10; $i += 10 ) {
            push @TicketYAxis, $i
        }
    }
    elsif ( $Max <= 1000 ) {
        for ( my $i = 0; $i <= ( ( ( $Max - $Max % 100 ) / 100 ) + 1 ) * 100; $i += 100 ) {
            push @TicketYAxis, $i
        }
    }
    else {
        for ( my $i = 0; $i <= ( ( ( $Max - $Max % 1000 ) / 1000 ) + 1 ) * 1000; $i += 1000 ) {
            push @TicketYAxis, $i
        }
    }
    my $ClosedText  = $LayoutObject->{LanguageObject}->Translate('Closed');
    my $CreatedText = $LayoutObject->{LanguageObject}->Translate('Created');

    my @ChartData;

    for my $Stat ( keys %Stats ) {
        push @ChartData, 
            {
                data  => $Stats{$Stat}->{data} || [],
                label => $Stats{$Stat}->{label} || $Stat,
                color => $Stats{$Stat}->{color} || '#cdcdcd',
            };
    }

    my $ChartDataJSON = $LayoutObject->JSONEncode(
        Data => \@ChartData,
    );

    my $TicketWeekdaysJSON = $LayoutObject->JSONEncode(
        Data => \@TicketWeekdays,
    );

    my $TicketYAxisJSON = $LayoutObject->JSONEncode(
        Data => \@TicketYAxis,
    );

    my %Data = (
        %{ $Self->{Config} },
        Key            => int rand 99999,
        ChartData      => $ChartDataJSON,
        TicketWeekdays => $TicketWeekdaysJSON,
        TicketYAxis    => $TicketYAxisJSON,
        Days           => $Days,
    );

    if ( $Self->{Config}->{CacheTTLLocal} ) {
        $Self->{CacheObject}->Set(
            Type  => 'Dashboard',
            Key   => $CacheKey,
            Value => \%Data,
            TTL   => $Self->{Config}->{CacheTTLLocal} * 60,
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile   => 'AgentDashboardTicketStats',
        Data           => \%Data,
        KeepScriptTags => $Param{AJAX},
    );

    return $Content;
}

1;
