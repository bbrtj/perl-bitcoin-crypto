use v5.10;
use strict;
use warnings;
use Test::More;
use Bitcoin::Crypto qw(btc_prv);
use Encode qw(encode);

use utf8;

BEGIN {
	unless (btc_prv->HAS_DETERMINISTIC_SIGNATURES) {
		plan skip_all => 'These tests require Crypt::Perl 0.34';
	}
}

my $key = btc_prv->from_hex('b7331fd4ff8c53d31fa7d1625df7de451e55dc53337db64bee3efadb7fdd28d9');
my @messages = ('Perl test script', '', 'a', "_ś\x1f " x 250);

my $case_num = 0;
for my $message (@messages) {
	subtest "testing deterministic signatures, case $case_num" => sub {
		$message = encode('UTF-8', $message);
		my $signature = $key->sign_message($message);

		ok($key->sign_message($message) eq $signature, 'Signatures generation should be deterministic');
		ok($key->verify_message($message, $signature), 'Valid signature');
	};

	++$case_num;
}

done_testing;

