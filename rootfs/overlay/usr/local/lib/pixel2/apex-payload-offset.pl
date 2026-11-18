# SPDX-License-Identifier: MIT
# print "<offset> <size> <method>" of apex_payload.img inside an .apex (zip)
open(my $f, '<:raw', $ARGV[0]) or die; local $/; my $d = <$f>;
my $pos = 0;
while (($pos = index($d, "PK\x03\x04", $pos)) >= 0) {
  my ($sig,$ver,$flag,$meth,$t,$dt,$crc,$csz,$usz,$nl,$xl) = unpack('VvvvvvVVVvv', substr($d,$pos,30));
  my $name = substr($d, $pos+30, $nl);
  if ($name eq 'apex_payload.img') { print $pos+30+$nl+$xl, " $usz $meth\n"; exit 0; }
  $pos += 30 + $nl + $xl + $csz;
}
exit 1;
