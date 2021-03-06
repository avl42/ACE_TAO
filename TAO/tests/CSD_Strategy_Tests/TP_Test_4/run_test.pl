eval '(exit $?0)' && eval 'exec perl -S $0 ${1+"$@"}'
     & eval 'exec perl -S $0 $argv:q'
     if 0;

# -*- perl -*-

use lib "$ENV{ACE_ROOT}/bin";
use PerlACE::TestTarget;

my $server = PerlACE::TestTarget::create_target (1) || die "Create target 1 failed\n";
my $client = PerlACE::TestTarget::create_target (2) || die "Create target 2 failed\n";

$server->AddLibPath ('../TP_Foo_A/.');
$server->AddLibPath ('../TP_Foo_B/.');
$server->AddLibPath ('../TP_Foo_C/.');
$server->AddLibPath ('../TP_Common/.');

$client->AddLibPath ('../TP_Foo_A/.');
$client->AddLibPath ('../TP_Foo_B/.');
$client->AddLibPath ('../TP_Foo_C/.');
$client->AddLibPath ('../TP_Common/.');

my $status = 0;

my $iorfname_prefix        = "servant";
my $num_servants           = 1;
my $num_orb_threads        = 1;
my $num_remote_clients     = 1;
my $num_csd_threads        = 1;
my $num_collocated_clients = 0;
my $collocated_client_kind = 0;
my $client_kind            = 0;

my $i;
my $j;
my @iorbase;
my @server_iorfile;
my @client_iorfile;

my $ARGC = @ARGV;

if ($ARGC > 0) {
    if ($ARGC > 1) {
        print STDERR "ERROR: Too many command-line arguments for $0.\n";
        exit 1;
    }

    my $subtest = $ARGV[0];

    if ($subtest eq 'remote') {
        $num_remote_clients = 40;
    }
    elsif ($subtest eq 'collocated') {
        $num_remote_clients = 0;
        $num_collocated_clients = 1;
    }
    elsif ($subtest eq 'collocated_big') {
        $num_remote_clients = 0;
        $num_csd_threads = 5;
        $num_collocated_clients = 40;
    }
    elsif ($subtest eq 'remote_orbthreads') {
        $num_orb_threads = 5;
        $num_remote_clients = 40;
    }
    elsif ($subtest eq 'remote_servants') {
        $num_servants = 5;
        $num_remote_clients = 40;
    }
    elsif ($subtest eq 'remote_csdthreads') {
        $num_csd_threads = 5;
        $num_remote_clients = 40;
    }
    elsif ($subtest eq 'remote_big') {
        $num_csd_threads = 5;
        $num_servants = 10;
        $num_orb_threads = 4;
        $num_remote_clients = 40;
    }
    elsif ($subtest eq 'big') {
        $num_csd_threads = 5;
        $num_servants = 10;
        $num_orb_threads = 4;
        $num_remote_clients = 40;
        $num_collocated_clients = 40;
    }
    elsif ($subtest eq 'usage') {
        print STDOUT "Usage: $0 [<subtest>]\n" .
                    "\n" .
                    "Supported <subtest> values:\n" .
                    "\n" .
                    "\tremote\n" .
                    "\tcollocated\n" .
                    "\tcollocated_big\n" .
                    "\tremote_orbthreads\n" .
                    "\tremote_servants\n" .
                    "\tremote_csdthreads\n" .
                    "\tremote_big\n" .
                    "\tbig\n" .
                    "\tusage\n" .
                    "\n";
        exit 0;
    }
    else {
        print STDERR "ERROR: invalid subtest argument for $0: $subtest\n";
        exit 1;
    }
}

#Fill array and delete old ior files.
for ($i = 0; $i < $num_servants; $i++) {
    my $servant_id = sprintf("%02d", ($i + 1));
    $iorbase[$i] = $iorfname_prefix . "_$servant_id.ior";
    $server_iorfile[$i] = $server->LocalFile($iorbase[$i]);
    $client_iorfile[$i] = $client->LocalFile($iorbase[$i]);
    $server->DeleteFile ($iorbase[$i]);
    $client->DeleteFile ($iorbase[$i]);
}
$server_fname = $server->LocalFile ($iorfname_prefix);

$SV = $server->CreateProcess ("server_main",
                              "-p $server_fname "           .
                              "-s $num_servants "           .
                              "-n $num_csd_threads "        .
                              "-t $num_orb_threads "        .
                              "-r $num_remote_clients "     .
                              "-c $num_collocated_clients " .
                              "-k $collocated_client_kind");
$SV->Spawn();

# Wait for the servant ior files created by server.
for ($i = 0; $i < $num_servants; $i++) {
    if ($server->WaitForFileTimed ($iorbase[$i],
                                   $server->ProcessStartWaitInterval()) == -1) {
        print STDERR "ERROR: cannot find file <$server_iorfile[$i]>\n";
        $SV->Kill(); $SV->TimedWait(1);
        exit 1;
    }
}

for ($i = 0; $i < $num_remote_clients; $i++) {

    $client_id = $i+1;

    $j = $i % $num_servants;
    $CLS[$i] = $client->CreateProcess ("client_main",
                                       "-i file://$client_iorfile[$j] ".
                                       "-k $client_kind ".
                                       "-n $client_id");
    $CLS[$i]->Spawn();
}

for ($i = 0; $i < $num_remote_clients; $i++) {
    $client_status = $CLS[$i]->WaitKill($client->ProcessStopWaitInterval () + 60);

    if ($client_status != 0) {
        print STDERR "ERROR: client $i returned $client_status\n";
        $status = 1;
    }
}

$server_status = $SV->WaitKill($server->ProcessStopWaitInterval () + 60);

if ($server_status != 0) {
    print STDERR "ERROR: server returned $server_status\n";
    $status = 1;
}

#Delete ior files generated by this run.
for ($i = 0; $i < $num_servants; $i++) {
    $server->DeleteFile ($iorbase[$i]);
    $client->DeleteFile ($iorbase[$i]);
}

exit $status;
