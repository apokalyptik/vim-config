#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path);
use JSON::PP;
use Digest::SHA;
use File::Path qw(make_path remove_tree);
use File::Copy qw(move);
my $root = abs_path("$FindBin::Bin/..");
my $platform = $^O eq 'darwin' ? 'darwin-arm64' : 'linux-x86_64';
my $profile = $ENV{VIM_CONFIG_PROFILE} || ($^O eq 'darwin' ? 'laptop' : 'container');
my $link_home = 0;
while (@ARGV) {
    my $arg = shift @ARGV;
    if ($arg eq '--profile') { $profile = shift(@ARGV) // die "Missing profile\n"; }
    elsif ($arg eq '--platform') { $platform = shift(@ARGV) // die "Missing platform\n"; }
    elsif ($arg eq '--link-home') { $link_home = 1; }
    else { die "Usage: bin/setup [--profile container|sandbox|misc|laptop|wsl] [--link-home]\n"; }
}
$profile =~ /\A(?:container|sandbox|misc|laptop|wsl)\z/ or die "Unknown profile\n";
$platform =~ /\A(?:darwin-arm64|linux-x86_64)\z/ or die "Unsupported platform\n";
my $arch = qx(uname -m); chomp $arch;
($arch eq 'arm64' && $^O eq 'darwin') || ($arch =~ /\A(?:x86_64|amd64)\z/ && $^O eq 'linux')
    or die "Supported hosts: macOS ARM64 and Linux x86-64 (including WSL)\n";
open my $manifest_fh, '<', "$root/tools/vendor-manifest.json" or die $!;
my $manifest;
{ local $/; $manifest = decode_json(<$manifest_fh>); }
close $manifest_fh;
my @payloads = grep { $_->{platform} eq $platform || $_->{platform} eq 'all' } @{$manifest->{payloads}};
make_path("$root/.state");
my $stage = "$root/.state/unpack-$$";
make_path($stage);
eval {
    for my $payload (@payloads) {
        @{$payload->{parts}} == 1 or die "Split archive unsupported by this installer\n";
        my $archive = "$root/$payload->{parts}[0]";
        open my $fh, '<:raw', $archive or die "Missing included payload: $archive\n";
        my $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;
        close $fh;
        $digest eq $payload->{sha256} or die "Checksum mismatch: $payload->{id}\n";
        my $dest = $payload->{destination};
        $dest !~ m{(?:\A/|(?:\A|/)\.\.(?:/|\z))} or die "Invalid payload destination\n";
        open my $listing, '-|', 'tar', '-tzf', $archive or die "Cannot list archive\n";
        while (my $name = <$listing>) {
            $name !~ m{(?:\A/|(?:\A|/)\.\.(?:/|\z))} or die "Unsafe archive path\n";
        }
        close $listing or die "Invalid archive: $payload->{id}\n";
        make_path("$stage/$dest");
        print "Unpacking $payload->{id}\n";
        system('tar', '-xzf', $archive, '-C', "$stage/$dest", '--strip-components=' . $payload->{strip_components}) == 0
            or die "Unpack failed: $payload->{id}\n";
    }
    make_path("$root/.state/tools");
    for my $name ($platform, 'shared') {
        next unless -d "$stage/$name";
        my $old = "$root/.state/previous-$name-$$";
        if (-e "$root/.state/tools/$name") {
            rename "$root/.state/tools/$name", $old or die "Cannot move old tools: $!\n";
        }
        if (!rename "$stage/$name", "$root/.state/tools/$name") {
            rename $old, "$root/.state/tools/$name" if -d $old;
            die "Cannot install tools: $!\n";
        }
        remove_tree($old) if -d $old;
    }
    open my $profile_fh, '>', "$root/.state/profile" or die $!;
    print {$profile_fh} "$profile\n";
    close $profile_fh;
    if ($link_home) {
        my $target = "$ENV{HOME}/.vimrc";
        if (-e $target || -l $target) {
            my $backup = $target . '.before-vim-config-' . time;
            rename $target, $backup or die "Cannot back up $target: $!\n";
            print "Previous vimrc saved as $backup\n";
        }
        symlink "$root/vimrc", $target or die "Cannot link $target: $!\n";
    }
    1;
} or do {
    my $error = $@;
    remove_tree($stage);
    die $error;
};
remove_tree($stage);
$ENV{VIM_CONFIG_HELP_DIR} = "$root/doc";
system('vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-c', 'execute "helptags " . fnameescape($VIM_CONFIG_HELP_DIR)', '-c', 'qa!') == 0
    or warn "Help tags could not be generated; the configuration can still start.\n";
print "Ready: profile=$profile platform=$platform\n";
print "Start: $root/bin/vim-config\n";
print "Verify: $root/bin/vim-config-doctor --profile $profile --lsp\n";
