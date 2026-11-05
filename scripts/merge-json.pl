#!/usr/bin/env perl
# merge-json.pl <file> <template>: add to <file> what <template> has and <file> lacks.
# Missing keys are added last, objects merge recursively, arrays gain their missing
# entries (an object entry, such as a hook, compared by content); nothing present is
# changed, removed or reordered. A missing <file> is created.
# Prints one "added" line per entry; no output = nothing was missing, file untouched.
# Exit 2 when <file> is not valid JSON (file untouched).
use strict; use warnings; use JSON::PP;

my ($file, $tpl) = @ARGV;
sub slurp { open my $h, '<:raw', $_[0] or die "$_[0]: $!\n"; local $/; <$h> }
my $text = -e $file ? slurp($file) : '{}';
my $json = JSON::PP->new->allow_nonref;
ref(eval { $json->decode($text) }) eq 'HASH' or do { print STDERR "not valid JSON: $file\n"; exit 2 };

# Order-keeping parse of JSON already known to be valid: an object is an O of
# [key, value, raw key] triples, an array an A of values, a scalar its raw text.
my $str = qr/"(?:[^"\\]|\\.)*"/;
sub val {
  /\G\s*/gc;
  if (/\G\{\s*/gc) {
    my @p;
    unless (/\G\}/gc) {
      do { /\G\s*($str)\s*:/gc; my $k = $1; push @p, [$json->decode($k), val(), $k]; /\G\s*/gc } while /\G,/gc;
      /\G\}/gc;
    }
    return bless \@p, 'O';
  }
  if (/\G\[\s*/gc) {
    my @a;
    unless (/\G\]/gc) { do { push @a, val(); /\G\s*/gc } while /\G,/gc; /\G\]/gc }
    return bless \@a, 'A';
  }
  /\G($str|[^\s,\]\}]+)/gc; return $1;
}
sub parse { local $_ = shift; val() }
my ($d, $t) = (parse($text), parse(slurp($tpl)));

# An array entry compared by content: an object (a hook entry) is the same entry whatever
# its key order or spacing.
sub plain { my $v = shift; ref $v eq 'O' ? { map { ($_->[0] => plain($_->[1])) } @$v }
  : ref $v eq 'A' ? [ map { plain($_) } @$v ] : $json->decode($v) }
my $canon = JSON::PP->new->canonical->allow_nonref;
sub canon { $canon->encode(plain($_[0])) }

my @added;
sub merge {
  my ($have, $want, $at) = @_;
  for my $w (@$want) {
    my ($k, $wv) = @$w;
    my ($h) = grep { $_->[0] eq $k } @$have;
    if (!$h) { push @$have, $w; push @added, "$at$k" }
    elsif (ref $h->[1] eq 'O' && ref $wv eq 'O') { merge($h->[1], $wv, "$at$k.") }
    elsif (ref $h->[1] eq 'A' && ref $wv eq 'A') {
      for my $e (@$wv) {
        my $c = canon($e);
        next if grep { canon($_) eq $c } @{$h->[1]};
        push @{$h->[1]}, $e; push @added, "$at$k += " . (ref $e ? $c : $json->decode($e));
      }
    }
  }
}
merge($d, $t, '');
exit 0 unless @added;

sub out {
  my ($v, $in) = @_;
  return $v unless ref $v;
  my ($o, $c) = ref $v eq 'O' ? ('{', '}') : ('[', ']');
  return "$o$c" unless @$v;
  my $i = "$in  ";
  my @e = ref $v eq 'O' ? map { "$i$_->[2]: " . out($_->[1], $i) } @$v : map { $i . out($_, $i) } @$v;
  "$o\n" . join(",\n", @e) . "\n$in$c";
}
open my $o, '>:raw', "$file.new" or die "$file.new: $!\n";
print $o out($d, ''), "\n"; close $o or die "$file.new: $!\n";
rename "$file.new", $file or die "$file: $!\n";
print "added   $file: $_\n" for @added;
