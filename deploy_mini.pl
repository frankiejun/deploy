#!/usr/bin/perl
##author: frankiejun@gmail.com
##date:   2014-06-19
use Getopt::Std;
use Config::Tiny;
#use Net::SSH::Perl;
use File::Basename;
use File::Path;
use File::Copy "mv";
use Cwd;
use String::Util qw(trim);
use Expect;
use POSIX qw(strftime);
use utf8;
binmode(STDOUT, ':encoding(utf8)');

use vars qw(%opt);

sub Usage {
	my $msg = "$0 usage: \n" .
		"-i   [指定配置文件, 必选]\n" .
		"-h   [帮助]\n";
    print $msg;
    exit;
}

#for default sending to '/tmp' diretory of remote host.
sub send_file {
    my ($ip, $usr, $pass, $file) = @_;
    print "ip:$ip|usr:$usr|pass:$pass|file:$file|\n";
    chomp($file);
    my $o = Expect->spawn("scp $file $usr\@$ip\:/tmp") 
        or die "Cannot spawn $command: $!\n";
    $o->raw_pty(1);
    my ( $pos, $err, $match, $before, $after ) = $o->expect(10,    
        [ qr/\(yes\/no\)\?\s*$/ => sub { $o->send("yes\n"); exp_continue; } ],  
        [ qr/assword:\s*$/  => sub { $o->send("$pass\n") if defined $pass; } ],
		[ qr/100\%/ => sub { exp_continue; }]);

    $o->soft_close();
}

sub remote_call {
    my ($ip, $usr, $pass, $root_pass, $shell_file) = @_;

    if( defined($shell_file)) {
        my $spawn = Expect->spawn("ssh $usr\@$ip");
        my $PROMPT  = '[\]\$\>\#]\s$';
        $spawn->log_stdout(0);

        $spawn->expect(3, 
            [ qr/\(yes\/no\)\?\s*$/ => sub { $spawn->send("yes\n"); exp_continue; } ],
            [ qr/assword:\s*$/  => sub { $spawn->send("$pass\n") if defined $pass; } ],);

        $spawn->send("su -\n") if $spawn->expect(undef, '-re' => qr/\[$usr.*$/);
        sleep(1); #hard to match chinese,just wait.
        $spawn->send("$root_pass\n") if $spawn->expect(undef, '-re' => qr/([\x80-\xFF][\x80-\xFF])*/);
        $spawn->send("/bin/bash /tmp/$shell_file  > /tmp/$shell_file.log 2>&1 \n") if $spawn->expect(undef, '-re' => qr/$PROMPT/);
        $spawn->send("exit\n") ;
        $spawn->send("exit\n") ;
        $spawn->soft_close();

    }
}

sub handle_each_host {
    my $s = shift;
	my $ip = $config->{$s}->{ip};
	my $usr = $config->{$s}->{usr};
	my $pass = $config->{$s}->{pass};
    my $root_pass= $config->{$s}->{root_pass};
	my $local_shell = $config->{$s}->{local_shell};
    print $local_shell;
    if(defined $local_shell ) {
        send_file($ip, $usr, $pass, $local_shell);
        my $shell_file = basename($local_shell);
        remote_call($ip, $usr, $pass, $root_pass, $shell_file);
    }
}

#handle each host.
sub go_to_host {
    my @sections = keys %$config;
    for(@sections) {
        if (/^to_.+?/) {
			print "$_\n";
            handle_each_host($_);
        }
    }
}

sub main {
    getopts("hi:", \%opt) or Usage();

    if($opt{i}) {
        $config = Config::Tiny->new;
        $config = Config::Tiny->read($opt{i});
        if(! $config) {
            print Config::Tiny->errstr;
            exit(-1);
        }
        go_to_host();
    }elsif($opt{h}) {
        Usage();
    }else{
        Usage();
    }

}


main();
