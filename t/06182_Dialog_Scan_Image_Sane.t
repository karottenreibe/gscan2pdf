use warnings;
use strict;
use Test::More tests => 2;
use Glib qw(TRUE FALSE);    # To get TRUE and FALSE
use Gtk3 -init;             # Could just call init separately
use Image::Sane ':all';     # To get SANE_* enums
use Sub::Override;    # Override Frontend::Image_Sane to test functionality that
                      # we can't with the test backend
use Storable qw(freeze);    # For cloning the options cache

BEGIN {
    use Gscan2pdf::Dialog::Scan::Image_Sane;
}

#########################

my $window = Gtk3::Window->new;

Gscan2pdf::Translation::set_domain('gscan2pdf');
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($WARN);
my $logger = Log::Log4perl::get_logger;

# The overrides must occur before the thread is spawned in setup.
my $override = Sub::Override->new;
$override->replace(
    'Gscan2pdf::Frontend::Image_Sane::_thread_get_devices' => sub {
        my ( $self, $uuid ) = @_;
        $self->{return}->enqueue(
            {
                type    => 'finished',
                process => 'get-devices',
                uuid    => $uuid,
                info    => freeze(
                    [
                        {
                            'name'  => 'mock_device',
                            'label' => 'mock_device'
                        }
                    ]
                ),
                status => SANE_STATUS_GOOD,
            }
        );
        return;
    }
);
$override->replace(
    'Gscan2pdf::Frontend::Image_Sane::_thread_open_device' => sub {
        my ( $self, $uuid, $device_name ) = @_;
        $self->{return}->enqueue(
            {
                type    => 'finished',
                process => 'open-device',
                uuid    => $uuid,
                info    => freeze( \$device_name ),
                status  => SANE_STATUS_GOOD,
            }
        );
        return;
    }
);

my $options = [
    undef,
    {
        'cap'        => 37,
        'constraint' => {
            'max'   => -444909896,
            'min'   => 0,
            'quant' => 32648
        },
        'constraint_type' => 1,
        'desc'            => 'Controls the brightness of the acquired image.',
        'index'           => 1,
        'max_values'      => 1,
        'name'            => 'brightness',
        'title'           => 'Brightness',
        'type'            => 1,
        'unit'            => 0
    },
];
$override->replace(
    'Gscan2pdf::Frontend::Image_Sane::_thread_get_options' => sub {
        my ( $self, $uuid ) = @_;
        $self->{return}->enqueue(
            {
                type    => 'finished',
                process => 'get-options',
                uuid    => $uuid,
                info    => freeze($options),
                status  => SANE_STATUS_GOOD,
            }
        );
        return;
    }
);

# $override->replace(
#     'Gscan2pdf::Frontend::Image_Sane::_thread_set_option' => sub {
#         my ( $self, $uuid, $index, $value ) = @_;
#         my $info = 0;
#         if ( $index == 1 and $value = 'Flatbed' ) {
#             $options->[2]{constraint} = [ 75, 100, 200, 300, 600, 1200 ];
#             $info = SANE_INFO_RELOAD_OPTIONS;
#         }
#         $options->[$index]{val} = $value;
#         $self->{return}->enqueue(
#             {
#                 type    => 'finished',
#                 process => 'set-option',
#                 uuid    => $uuid,
#                 status  => SANE_STATUS_GOOD,
#                 info    => $info,
#             }
#         );
#         return;
#     }
# );

Gscan2pdf::Frontend::Image_Sane->setup($logger);

my $dialog = Gscan2pdf::Dialog::Scan::Image_Sane->new(
    title           => 'title',
    'transient-for' => $window,
    'logger'        => $logger
);

$dialog->{signal} = $dialog->signal_connect(
    'changed-device-list' => sub {
        $dialog->signal_handler_disconnect( $dialog->{signal} );
        is_deeply(
            $dialog->get('device-list'),
            [
                {
                    'name'  => 'mock_device',
                    'model' => 'mock_device',
                    'label' => 'mock_device'
                }
            ],
            'successfully mocked getting device list'
        );
        $dialog->set( 'device', 'mock_device' );
    }
);

$dialog->{reloaded_signal} = $dialog->signal_connect(
    'reloaded-scan-options' => sub {
        $dialog->signal_handler_disconnect( $dialog->{reloaded_signal} );
        pass "successfully created dialog, ignoring option with min>max";
        Gtk3->main_quit;
    }
);
$dialog->get_devices;

Gtk3->main;

Gscan2pdf::Frontend::Image_Sane->quit;
__END__
