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
use perluim::filemap;

#
# Declare default script variables & declare log class.
#
my $time = time();
my $version = "1.5";
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
my $alarm_severity      = $CFG->{"monitoring"}->{"alarm_severity"} || 2;
my $alarm_subsys        = $CFG->{"monitoring"}->{"alarm_subsys"} || "1.1.1.1";
my %ProbesList = (); 

$Console->print("Loading probes_list !");
foreach my $probeName (keys $CFG->{"probes_list"}) {
    $Console->print("Load probe $probeName. ");
    $ProbesList{$probeName} = {
        callback => $CFG->{"probes_list"}->{$probeName}->{'callback'}
    };
}
$Console->print('---------------------------------------',5);

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
perluim::utils::createDirectory("$Output_directory/$Execution_Date");
$Console->cleanDirectory("$Output_directory",$Cache_delay);

my $filemap = new perluim::filemap('temporary_alarms.cfg');

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

    my ($RC,@RobotsList) = $hub->local_robotsArray();
    if($RC == NIME_OK) {

        $Console->print("Starting processing robots",5);

        # Foreach robots
        my $probe_down = 0;
        foreach my $robot (@RobotsList) {

            $Console->print('',5);
            $Console->print("Start processing of $robot->{name} probes",5);
            $Console->print('',5);

            my ($RC_Probe,@ProbesArr) = $robot->local_probesArray();
            if($RC_Probe == NIME_OK) {

                foreach my $probe (@ProbesArr) {
                    next if not exists($ProbesList{$probe->{name}}); 
                    my $generate_alarm = 0;
                    $Console->print("processing $probe->{name}",3);
                    my $callback = $ProbesList{$probe->{name}}{callback};

                    if($probe->{active}) {
                        my $pds = new Nimbus::PDS(); 
                        my $i_retry = 3;
                        my $i_fail = "ko";
                        while($i_retry--) {
                            my ($cb_rc,$res);
                            if(not defined $probe->{port}) {
                                ($cb_rc,$res) = nimNamedRequest("$robot->{addr}",$callback,$pds->data());
                            }
                            else {
                                ($cb_rc,$res) = nimRequest("$robot->{name}",$probe->{port},$callback,$pds->data());
                            }
                            if($cb_rc != NIME_OK) {
                                $Console->print("Failed to execute $callback with rc $cb_rc",1);
                                $|=1;
                                perluim::utils::doSleep(2);
                            }
                            else {
                                $Console->print("OK...",6);
                                $i_fail = "ok";
                                last;
                            }
                        }

                        if($i_fail eq "ko" && $launch_alarm eq "yes") {
                            $generate_alarm = 1;
                            $probe_down++;
                        }
                    }
                    else {
                        $Console->print("Probe inactive - KO...");
                        $generate_alarm = 1;
                    }

                    my $cb_identifier = "robotscheck_cbfail_$robot->{name}_$probe->{name}";

                    if($generate_alarm and not $Audit) {
                        my %AlarmObject = (
                            severity => $alarm_severity,
                            message => "Callback $callback return error for probe $probe->{name}",
                            robot => "$robot->{name}",
                            domain => "$Domain",
                            probe => "robots_checker",
                            origin => "$robot->{origin}",
                            source => "$robot->{ip}",
                            dev_id => "$robot->{device_id}",
                            met_id => "$robot->{metric_id}",
                            subsystem => $alarm_subsys,
                            suppression => "$cb_identifier",
                            usertag1 => "$robot->{os_user1}",
                            supp_key => "$cb_identifier",
                            usertag2 => "$robot->{os_user2}"
                        );
                        my ($PDS,$alarmid) = perluim::utils::generateAlarm('alarm',\%AlarmObject);
                        my ($rc_alarm,$res) = nimRequest("$robot->{name}",48001,"post_raw",$PDS->data);
                        if($rc_alarm == NIME_OK) {
                            $Console->print("Generating alarm with id => $alarmid for probe $probe->{name}",2);
                            my %Args = (
                                suppkey => "$cb_identifier"
                            );
                            $filemap->set($cb_identifier, \%Args );
                            $filemap->writeToDisk();
                        }
                        else {
                            $Console->print("Failed to generate new alarm (RC: $rc_alarm) - Robot: $robot->{name}",2);
                        }
                    }
                    else {
                        if($filemap->has($cb_identifier)) {
                            my %AlarmObject = (
                                severity => 0,
                                message => "Callback $callback return error for probe $probe->{name}",
                                domain => "$Domain",
                                robot => "$robot->{name}",
                                probe => "robots_checker",
                                source => "$robot->{ip}",
                                origin => "$robot->{origin}",
                                dev_id => "$robot->{device_id}",
                                met_id => "$robot->{metric_id}",
                                subsystem => $alarm_subsys,
                                supp_key => "$cb_identifier",
                                suppression => "$cb_identifier",
                                usertag1 => "$robot->{os_user1}",
                                usertag2 => "$robot->{os_user2}"
                            );
                            my ($PDS,$alarmid) = perluim::utils::generateAlarm('alarm',\%AlarmObject);
                            my ($rc_alarm,$res) = nimRequest("$robot->{name}",48001,"post_raw",$PDS->data);
                            if($rc_alarm == NIME_OK) {
                                $Console->print("Generating alarm clear with id => $alarmid");
                                $filemap->delete($cb_identifier);
                                $filemap->writeToDisk();
                            }
                            else {
                                $Console->print("Failed to generate new alarm clear with RC $rc_alarm",2);
                            }
                        }
                    }

                }
                
            }
            else {
                $Console->print("Failed to execute callback probe_list on $robot->{name}",1);
            }
        }

        $Console->print('',5);
        $Console->print("Robots processing done! Probe down count => $probe_down");

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
    sleep(2);
    $Console->copyTo("output/$Execution_Date");
    $filemap->writeToDisk();
}

#
# When application is breaked with CTRL+C
#
sub breakApplication { 
    $Console->print("\n\n Application breaked with CTRL+C \n\n",0);
    sleep(2);
    $Console->copyTo("output/$Execution_Date");
    $filemap->writeToDisk();
    exit(1);
}

# Call the main method 
main();
$filemap->writeToDisk();

$Console->finalTime($time);
sleep(2);
$Console->copyTo($Final_directory);
$Console->close();
