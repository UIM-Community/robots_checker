# use dependencies
use strict;
use warnings;
use lib "D:/apps/Nimsoft/perllib";
use lib "D:/apps/Nimsoft/Perl64/lib/Win32API";
use Data::Dumper;
use Nimbus::API;
use Nimbus::CFG;
use Nimbus::PDS;
use perluim::log;
use perluim::main;
use perluim::alarmsmanager;
use perluim::utils;
use perluim::file;

#
# Declare default script variables & declare log class.
#
my $time = time();
my $version = "1.0";
my ($Console,$SDK,$Execution_Date,$Final_directory);
$Execution_Date = perluim::utils::getDate();
$Console = new perluim::log('robots_checker.log',6,0,'yes');

# Handle critical errors & signals!
$SIG{__DIE__} = \&trap_die;
$SIG{INT} = \&breakApplication;

# Start logging
$Console->print('---------------------------------------',5);
$Console->print('Robots_checker started at '.localtime(),5);
$Console->print("Version $version",5);
$Console->print('---------------------------------------',5);

#
# Open and append configuration variables
#
my $CFG                 = Nimbus::CFG->new("robots_checker.cfg");
my $Domain              = $CFG->{"setup"}->{"domain"} || undef;
my $Cache_delay         = $CFG->{"setup"}->{"output_cache_time"} || 432000;
my $Audit               = $CFG->{"setup"}->{"audit"} || 0;
my $Output_directory    = $CFG->{"setup"}->{"output_directory"} || "output";
my $Login               = $CFG->{"setup"}->{"nim_login"} || undef;
my $Password            = $CFG->{"setup"}->{"nim_password"} || undef;
my $launch_alarm        = $CFG->{"monitoring"}->{"alarms_probes_down"} || "no";
my %ProbesList = (); 

$Console->print("Loading probes_list !");
foreach my $probeName (keys $CFG->{"probes_list"}) {
    $Console->print("Load probe $probeName. ");
    $ProbesList{$probeName} = {
        callback => $CFG->{"probes_list"}->{$probeName}->{'callback'}
    };
}
$Console->print('---------------------------------------',5);

# Declare alarms_manager
my $alarm_manager = new perluim::alarmsmanager($CFG,"alarm_messages");

# Check if domain is correctly configured
if(not defined($Domain)) {
    trap_die('Domain is not declared in the configuration file!');
    exit(1);
}

#
# Print configuration file
#
$Console->print("Print configuration setup section : ",5);
foreach($CFG->getKeys($CFG->{"setup"})) {
    $Console->print("Configuration : $_ => $CFG->{setup}->{$_}",5);
}
$Console->print('---------------------------------------',5);

#
# nimLogin if login and password are defined in the configuration!
#
nimLogin($Login,$Password) if defined($Login) && defined($Password);

#
# Declare framework, create / clean output directory.
# 
$SDK                = new perluim::main("$Domain");
$Final_directory    = "$Output_directory/$Execution_Date";
$SDK->createDirectory("$Output_directory/$Execution_Date");
$Console->cleanDirectory("$Output_directory",$Cache_delay);

#
# Main method to call for the script ! 
# main();
# executed at the bottom of this script.
# 
sub main {
    my ($RC,$hub) = $SDK->getLocalHub();
    if($RC == NIME_OK) {
        $Console->print("Start processing $hub->{name} !!!",5);
        $Console->print('---------------------------------------',5);
        my $RC_ROBOT = checkRobots($hub);
        return $RC_ROBOT;
    }
    else {
        $Console->print('Failed to get hub',0);
        return 0;
    }
}

#
# Method to check all the robots from a specific hub object.
# checkRobots($hub);
# used in main() method.
# 
sub checkRobots {
    my ($hub) = @_;

    my ($RC,@RobotsList) = $hub->getLocalRobots();
    if($RC == NIME_OK) {

        $Console->print("Starting processing robots",5);

        # Foreach robots
        my $probe_down = 0;
        foreach my $robot (@RobotsList) {

            $Console->print('---------------------------------------',5);
            $Console->print("Start processing of $robot->{name} probes",5);
            $Console->print('---------------------------------------',5);

            my ($RC_Probe,@ProbesList) = $robot->getLocalArrayProbes();
            if($RC_Probe == NIME_OK) {

                foreach my $probe (@ProbesList) {
                    next if not exists($ProbesList{$probe->{name}}); 
                    my $generate_alarm = 0;
                    $Console->print(">> $probe->{name}");
                    my $callback = $ProbesList{$probe->{name}}{callback};

                    if($probe->{active}) {
                        my $pds = new Nimbus::PDS(); 
                        my ($cb_rc,$res) = nimRequest("$robot->{name}",$probe->{port},$callback,$pds->data());
                        if($cb_rc != NIME_OK) {
                            $Console->print("Failed to execute $callback");
                            if($launch_alarm eq "yes") {
                                $generate_alarm = 1;
                                $probe_down++;
                            }
                        }
                        else {
                            $Console->print("OK...",6);
                        }
                    }
                    else {
                        $generate_alarm = 1;
                    }

                    if($generate_alarm and not $Audit) {
                        my $alarm = $alarm_manager->get('probe_down');
                        my ($rc_alarm,$alarmid) = $alarm->call({
                            callback => "$callback",
                            probe => "$probe->{name}",
                            robotName => "$robot->{name}",
                            hubName => "$hub->{name}"
                        });

                        if($rc_alarm == NIME_OK) {
                            $Console->print("Generating alarm with id => $alarmid");
                        }
                        else {
                            $Console->print("Failed to generate new alarm",2);
                        }
                    }

                }
                
            }
            else {
                $Console->print("Failed to execute callback probe_list on $robot->{name}",1);
            }
        }

        $Console->print("Robots processing done! Probe down count => $probe_down");
        $Console->print('---------------------------------------',5);

        return 1;
    }
    else {
        $Console->print('Failed to get robotslist from hub',0);
        return 0;
    }
}

#
# Die method
# trap_die($error_message)
# 
sub trap_die {
    my ($err) = @_;
	$Console->print("Program is exiting abnormally : $err",0);
    $| = 1; # Buffer I/O fix
    sleep(2);
    $Console->copyTo("output/$Execution_Date");
}

#
# When application is breaked with CTRL+C
#
sub breakApplication { 
    $Console->print("\n\n Application breaked with CTRL+C \n\n",0);
    $| = 1; # Buffer I/O fix
    sleep(2);
    $Console->copyTo("output/$Execution_Date");
    exit(1);
}

# Call the main method 
main();

$Console->finalTime($time);
$| = 1; # Buffer I/O fix
sleep(2);
$Console->copyTo($Final_directory);
$Console->close();
