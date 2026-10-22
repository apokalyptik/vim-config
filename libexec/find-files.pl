#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
my ($root, @excluded_names) = @ARGV;
defined $root or die "find-files: missing root\n";
my %skip = map { $_ => 1 } @excluded_names;
my @deny = grep { length } split /\n/, ($ENV{VIM_CONFIG_DENY_PATHS} // '');
my %seen;
my $count = 0;
sub allowed {
    my ($path) = @_;
    for my $deny (@deny) {
        return 0 if $path eq $deny || index($path, "$deny/") == 0;
    }
    return 0 if ($ENV{VIM_CONFIG_PROFILE} // '') eq 'sandbox' && $path =~ m{/wp-content/blogs\.dir(?:/|$)};
    return 1;
}
sub walk {
    my ($dir, $relative) = @_;
    return if $count >= 20000 || !allowed($dir);
    my @info = stat($dir);
    return unless @info && !$seen{"$info[0]:$info[1]"}++;
    opendir(my $handle, $dir) or return;
    while (defined(my $name = readdir($handle))) {
        next if $name eq '.' || $name eq '..' || $skip{$name} || $name =~ /[\r\n\t]/;
        my $path = "$dir/$name";
        next unless allowed($path);
        my $rel = length($relative) ? "$relative/$name" : $name;
        if (-d $path) { walk($path, $rel); }
        elsif (-f $path) { print "$rel\n"; $count++; }
        last if $count >= 20000;
    }
    closedir($handle);
}
allowed($root) or die "find-files: excluded root\n";
my $candidate = $root;
while ($candidate ne '/') {
    if (-d "$candidate/.git" || -f "$candidate/.git" || -d "$candidate/.svn" || -f "$candidate/wp-config.php" || -f "$candidate/composer.json" || -f "$candidate/go.mod") {
        $root = $candidate;
        last;
    }
    $candidate = dirname($candidate);
}
print "ROOT\t$root\n";
walk($root, '');
