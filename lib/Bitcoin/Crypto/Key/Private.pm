package Bitcoin::Crypto::Key::Private;

use Modern::Perl "2010";
use Moo;
use MooX::Types::MooseLike::Base qw(Str);
use Crypt::PK::ECC;
use Bitcoin::BIP39 qw(bip39_mnemonic_to_entropy entropy_to_bip39_mnemonic);
use List::Util qw(first);

use Bitcoin::Crypto::Key::Public;
use Bitcoin::Crypto::Base58 qw(encode_base58check decode_base58check);
use Bitcoin::Crypto::Config;
use Bitcoin::Crypto::Network qw(find_network get_network);
use Bitcoin::Crypto::Util qw(validate_wif);
use Bitcoin::Crypto::Helpers qw(ensure_length);
use Bitcoin::Crypto::Exception;

with "Bitcoin::Crypto::Role::BasicKey";

sub _isPrivate { 1 }

sub toWif
{
	my ($self) = @_;
	my $bytes = $self->toBytes();
	# wif network - 1B
	my $wifdata = $self->network->{wif_byte};
	# key entropy - 32B
	$wifdata .= ensure_length $bytes, $config{key_max_length};
	# additional byte for compressed key - 1B
	$wifdata .= $config{wif_compressed_byte} if $self->compressed;

	return encode_base58check($wifdata);
}

sub fromWif
{
	my ($class, $wif, $network) = @_;

	Bitcoin::Crypto::Exception->raise(
		code => "key_create",
		message => "base58 string is not valid WIF"
	) unless validate_wif($wif);

	my $decoded = decode_base58check($wif);
	my $private = substr $decoded, 1;

	my $compressed = 0;
	if (length($private) > $config{key_max_length}) {
		chop $private;
		$compressed = 1;
	}

	my $wif_network_byte = substr $decoded, 0, 1;
	my @found_networks = find_network(wif_byte => $wif_network_byte);
	@found_networks = first { $_ eq $network } @found_networks if defined $network;

	Bitcoin::Crypto::Exception->raise(
		code => "key_create",
		message => "found multiple networks possible for given WIF"
	) if @found_networks > 1;

	Bitcoin::Crypto::Exception->raise(
		code => "key_create",
		message => "network name $network cannot be used for given WIF"
	) if @found_networks == 0 && defined $network;

	Bitcoin::Crypto::Exception->raise(
		code => "network_config",
		message => "couldn't find network for WIF byte $wif_network_byte"
	) if @found_networks == 0;

	my $instance = $class->fromBytes($private);
	$instance->setCompressed($compressed);
	$instance->setNetwork(@found_networks);
	return $instance;
}

sub getPublicKey
{
	my ($self) = @_;

	my $public = Bitcoin::Crypto::Key::Public->new($self->rawKey("public"));
	$public->setCompressed($self->compressed);
	$public->setNetwork($self->network);
	return $public;
}

1;

__END__
=head1 NAME

Bitcoin::Crypto::Key::Private - class for Bitcoin private keys

=head1 SYNOPSIS

	use Bitcoin::Crypto::Key::Private;

	# get Bitcoin::Crypto::Key::Public instance from private key

	my $pub = $priv->getPublicKey();

	# create signature using private key (sha256 of string byte representation)

	my $sig = $priv->signMessage("Hello world");

	# signature is returned as byte string
	# use unpack to get the representation you need

	my $sig_hex = unpack "H*", $sig;

	# signature verification

	$priv->verifyMessage("Hello world", $sig);

=head1 DESCRIPTION

This class allows you to create a private key instance.

You can use a private key to:

=over 2

=item * generate public keys

=item * sign and verify messages

=back

Please note that any keys generated are by default compressed.

see L<Bitcoin::Crypto::Network> if you want to work with other networks than Bitcoin Mainnet.

=head1 METHODS

=head2 fromBytes

	sig: fromBytes($class, $data)
Use this method to create a PrivateKey instance from a byte string.
Data $data will be used as a private key entropy.
Returns class instance.

=head2 new

	sig: new($class, $data)
This works exactly the same as fromBytes

=head2 toBytes

	sig: toBytes($self)
Does the opposite of fromBytes on a target object

=head2 fromHex

	sig: fromHex($class, $hex)
Use this method to create a PrivateKey instance from a hexadecimal number.
Number $hex will be used as a private key entropy.
Returns class instance.

=head2 toHex

	sig: toHex($self)
Does the opposite of fromHex on a target object

=head2 fromWif

	sig: fromWif($class, $str, $network = undef)
Creates a new private key from Wallet Import Format string.
Takes an additional optional argument, which is network name. It may
be useful if you use many networks and some have the same WIF byte.
This method will change compression and network states of the created private key,
as this data is included in WIF format.
Will fail with 0 / undef if passed WIF string is invalid.
Will croak if it encounters a problem with network configuration.
Returns class instance.

=head2 toWif

	sig: toWif($self)
Does the opposite of fromWif on a target object

=head2 setCompressed

	sig: setCompressed($self, $val)
Change key's compression state to $val (1/0). This will change the WIF generated by
toWif() method and also enable creation of uncompressed public keys.
If $val is omitted it is set to 1.
Returns current key instance.

=head2 setNetwork

	sig: setNetwork($self, $val)
Change key's network state to $val. It can be either network name present in
Bitcoin::Crypto::Network package or a valid network hashref. This will change the
WIF generated by toWif() method and also enable creation of public keys
generating this network's addresses.
Returns current key instance.

=head2 getPublicKey

	sig: getPublicKey($self)
Returns instance of L<Bitcoin::Crypto::PublicKey> generated from the private key.

=head2 signMessage

	sig: signMessage($self, $message, $algo = "sha256")
Signs a digest of $message (using $algo digest algorithm) with a private key.
$algo must be available in L<Digest> package.
Returns a byte string containing signature.

=head2 verifyMessage

	sig: verifyMessage($self, $message, $signature, $algo = "sha256")
Verifies $signature against digest of $message (with $algo digest algorithm)
using private key.
$algo must be available in Digest package.
Returns boolean.

=head1 SEE ALSO

=over 2

=item L<Bitcoin::Crypto::Key::Public>

=item L<Bitcoin::Crypto::Network>

=back

=cut