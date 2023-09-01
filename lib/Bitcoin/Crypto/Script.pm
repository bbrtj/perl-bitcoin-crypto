package Bitcoin::Crypto::Script;

use v5.10;
use strict;
use warnings;
use Moo;
use Crypt::Digest::SHA256 qw(sha256);
use Mooish::AttributeBuilder -standard;
use Try::Tiny;
use Scalar::Util qw(blessed);
use Type::Params -sigs;

use Bitcoin::Crypto::Constants;
use Bitcoin::Crypto::Base58 qw(encode_base58check decode_base58check);
use Bitcoin::Crypto::Bech32 qw(encode_segwit decode_segwit);
use Bitcoin::Crypto::Constants;
use Bitcoin::Crypto::Helpers qw(carp_once);
use Bitcoin::Crypto::Util qw(hash160 hash256);
use Bitcoin::Crypto::Exception;
use Bitcoin::Crypto::Types qw(Maybe ArrayRef HashRef Str Object ByteStr Any ScriptType ScriptDesc);
use Bitcoin::Crypto::Script::Opcode;
use Bitcoin::Crypto::Script::Runner;

use namespace::clean;

has field '_serialized' => (
	isa => Str,
	writer => 1,
	default => '',
);

has param 'type' => (
	isa => Maybe [ScriptType],
	required => 0,
	lazy => 1,
	predicate => -hidden,
);

with qw(Bitcoin::Crypto::Role::Network);

sub _build
{
	my ($self, $address) = @_;
	my $type = $self->type;

	state $types = do {
		my $witness = sub {
			my ($self, $address, $name, $version, $length) = @_;

			my $data = decode_segwit $address;
			my $this_version = substr $data, 0, 1, '';

			Bitcoin::Crypto::Exception::SegwitProgram->raise(
				"$name script only handles witness version $version"
			) unless $this_version eq chr $version;

			Bitcoin::Crypto::Exception::SegwitProgram->raise(
				"$name script should contain $length bytes"
			) unless length $data eq $length;

			$self
				->push(chr $version)
				->push($data);
		};

		{
			P2PK => sub {
				my ($self, $pubkey) = @_;

				$self
					->push($pubkey)
					->add('OP_CHECKSIG');
			},

			P2PKH => sub {
				my ($self, $address) = @_;

				$self
					->add('OP_DUP')
					->add('OP_HASH160')
					->push(substr decode_base58check($address), 1)
					->add('OP_EQUALVERIFY')
					->add('OP_CHECKSIG');
			},

			P2SH => sub {
				my ($self, $address) = @_;

				$self
					->add('OP_HASH160')
					->push(substr decode_base58check($address), 1)
					->add('OP_EQUAL');
			},

			P2MS => sub {
				my ($self, $data) = @_;

				die 'P2MS script argument must be an array reference'
					unless ref $data eq 'ARRAY';

				my ($signatures_num, @pubkeys) = @$data;

				die 'P2MS script first element must be a number between 1 and 15'
					unless $signatures_num >= 0 && $signatures_num <= 15;

				die 'P2MS script remaining elements number should be between the number of signatures and 15'
					unless @pubkeys >= $signatures_num && @pubkeys <= 15;

				$self->push(chr $signatures_num);

				foreach my $pubkey (@pubkeys) {
					$self->push($pubkey);
				}

				$self
					->push(chr scalar @pubkeys)
					->add('OP_CHECKMULTISIG');
			},

			P2WPKH => sub {
				$witness->(@_, 'P2WPKH', 0, 20);
			},

			P2WSH => sub {
				$witness->(@_, 'P2WSH', 0, 32);
			},

			NULLDATA => sub {
				my ($self, $data) = @_;

				$self
					->add('OP_RETURN')
					->push($data);
			},
		};
	};

	Bitcoin::Crypto::Exception::ScriptType->raise(
		"unknown standard script type $type"
	) if !$types->{$type};

	Bitcoin::Crypto::Exception::ScriptPush->trap_into(
		sub {
			$types->{$type}->($self, $address);
		}
	);

	return;
}

sub _build_type
{
	my ($self) = @_;

	# blueprints for standard transaction types
	state $types = [
		[
			P2PK => [
				['data', 33, 65],
				'OP_CHECKSIG',
			]
		],

		[
			P2PKH => [
				'OP_DUP',
				'OP_HASH160',
				['data', 20],
				'OP_EQUALVERIFY',
				'OP_CHECKSIG',
			]
		],

		[
			P2SH => [
				'OP_HASH160',
				['data', 20],
				'OP_EQUAL',
			]
		],

		[
			P2MS => [
				['op_n', 1 .. 15],
				['data_repeated', 33, 65],
				['op_n', 1 .. 15],
				'OP_CHECKMULTISIG',
			]
		],

		[
			P2WPKH => [
				'OP_0',
				['data', 20],
			],
		],

		[
			P2WSH => [
				'OP_0',
				['data', 32],
			]
		],

		[
			NULLDATA => [
				'OP_RETURN',
				['data', 1 .. 75],
			]
		],

		[
			NULLDATA => [
				'OP_RETURN',
				'OP_PUSHDATA1',
				['data', 76 .. 80],
			]
		],
	];

	my $this_script = $self->_serialized;
	my $check_blueprint;
	$check_blueprint = sub {
		my ($pos, $part, @more_parts) = @_;

		return $pos == length $this_script
			unless defined $part;
		return !!0 unless $pos < length $this_script;

		if (!ref $part) {
			my $opcode = Bitcoin::Crypto::Script::Opcode->get_opcode_by_name($part);
			return !!0 unless $opcode->code eq substr $this_script, $pos, 1;
			return $check_blueprint->($pos + 1, @more_parts);
		}
		else {
			my ($kind, @vars) = @$part;

			if ($kind eq 'data') {
				my $len = ord substr $this_script, $pos, 1;

				return !!0 unless grep { $_ == $len } @vars;
				return !!1 if $check_blueprint->($pos + $len + 1, @more_parts);
			}
			elsif ($kind eq 'data_repeated') {
				my $count = 0;
				while (1) {
					my $len = ord substr $this_script, $pos, 1;
					last unless grep { $_ == $len } @vars;

					$pos += $len + 1;
					$count += 1;
				}

				return !!0 if $count == 0 || $count > 16;
				my $opcode = Bitcoin::Crypto::Script::Opcode->get_opcode_by_name("OP_$count");
				return !!0 unless $opcode->code eq substr $this_script, $pos, 1;
				return $check_blueprint->($pos, @more_parts);
			}
			elsif ($kind eq 'op_n') {
				my $opcode;
				try {
					$opcode = Bitcoin::Crypto::Script::Opcode->get_opcode_by_code(substr $this_script, $pos, 1);
				};

				return !!0 unless $opcode;
				return !!0 unless $opcode->name =~ /\AOP_(\d+)\z/;
				return !!0 unless grep { $_ == $1 } @vars;
				return $check_blueprint->($pos + 1, @more_parts);
			}
			else {
				die "invalid blueprint kind: $kind";
			}
		}
	};

	my $ret = undef;
	foreach my $type_def (@$types) {
		my ($type, $blueprint) = @{$type_def};

		if ($check_blueprint->(0, @$blueprint)) {
			$ret = $type;
			last;
		}
	}

	# make sure no memory leak occurs
	$check_blueprint = undef;
	return $ret;
}

sub BUILD
{
	my ($self, $args) = @_;

	if ($self->_has_type) {
		Bitcoin::Crypto::Exception::ScriptPush->raise(
			'script with a "type" also requires an "address"'
		) unless $args->{address};

		$self->_build($args->{address});
	}
}

signature_for operations => (
	method => Object,
	positional => [],
);

sub operations
{
	my ($self) = @_;

	my $serialized = $self->_serialized;
	my @ops;

	my $data_push = sub {
		my ($size) = @_;

		Bitcoin::Crypto::Exception::ScriptSyntax->raise(
			'not enough bytes of data in the script'
		) if length $serialized < $size;

		return substr $serialized, 0, $size, '';
	};

	my %context = (
		op_if => undef,
		op_else => undef,
		previous_context => undef,
	);

	my %special_ops = (
		OP_PUSHDATA1 => sub {
			my ($op) = @_;
			my $raw_size = substr $serialized, 0, 1, '';
			my $size = unpack 'C', $raw_size;

			push @$op, $data_push->($size);
			$op->[1] .= $raw_size . $op->[2];
		},
		OP_PUSHDATA2 => sub {
			my ($op) = @_;
			my $raw_size = substr $serialized, 0, 2, '';
			my $size = unpack 'v', $raw_size;

			push @$op, $data_push->($size);
			$op->[1] .= $raw_size . $op->[2];
		},
		OP_PUSHDATA4 => sub {
			my ($op) = @_;
			my $raw_size = substr $serialized, 0, 4, '';
			my $size = unpack 'V', $raw_size;

			push @$op, $data_push->($size);
			$op->[1] .= $raw_size . $op->[2];
		},
		OP_IF => sub {
			my ($op) = @_;

			if ($context{op_if}) {
				%context = (
					previous_context => {%context},
				);
			}
			$context{op_if} = $op;
		},
		OP_ELSE => sub {
			my ($op, $pos) = @_;

			Bitcoin::Crypto::Exception::ScriptSyntax->raise(
				'OP_ELSE found but no previous OP_IF or OP_NOTIF'
			) if !$context{op_if};

			Bitcoin::Crypto::Exception::ScriptSyntax->raise(
				'multiple OP_ELSE for a single OP_IF'
			) if @{$context{op_if}} > 2;

			$context{op_else} = $op;

			push @{$context{op_if}}, $pos;
		},
		OP_ENDIF => sub {
			my ($op, $pos) = @_;

			Bitcoin::Crypto::Exception::ScriptSyntax->raise(
				'OP_ENDIF found but no previous OP_IF or OP_NOTIF'
			) if !$context{op_if};

			push @{$context{op_if}}, undef
				if @{$context{op_if}} == 2;
			push @{$context{op_if}}, $pos;

			if ($context{op_else}) {
				push @{$context{op_else}}, $pos;
			}

			if ($context{previous_context}) {
				%context = %{$context{previous_context}};
			}
			else {
				%context = ();
			}
		},
	);

	$special_ops{OP_NOTIF} = $special_ops{OP_IF};
	my @debug_ops;
	my $position = 0;

	try {
		while (length $serialized) {
			my $this_byte = substr $serialized, 0, 1, '';

			try {
				my $opcode = Bitcoin::Crypto::Script::Opcode->get_opcode_by_code($this_byte);
				push @debug_ops, $opcode->name;
				my $to_push = [$opcode, $this_byte];

				if (exists $special_ops{$opcode->name}) {
					$special_ops{$opcode->name}->($to_push, $position);
				}

				push @ops, $to_push;
			}
			catch {
				my $err = $_;

				my $opcode_num = ord($this_byte);
				unless ($opcode_num > 0 && $opcode_num <= 75) {
					push @debug_ops, unpack 'H*', $this_byte;
					die $err;
				}

				# NOTE: compiling standard data push into PUSHDATA1 for now
				my $opcode = Bitcoin::Crypto::Script::Opcode->get_opcode_by_name('OP_PUSHDATA1');
				push @debug_ops, $opcode->name;

				my $raw_data = $data_push->($opcode_num);
				push @ops, [$opcode, $this_byte . $raw_data, $raw_data];
			};

			$position += 1;
		}

		Bitcoin::Crypto::Exception::ScriptSyntax->raise(
			'some OP_IFs were not closed'
		) if $context{op_if};
	}
	catch {
		my $ex = $_;
		if (blessed $ex && $ex->isa('Bitcoin::Crypto::Exception::ScriptSyntax')) {
			$ex->set_script(\@debug_ops);
			$ex->set_error_position($position);
		}

		die $ex;
	};

	return \@ops;
}

signature_for add_raw => (
	method => Object,
	positional => [ByteStr],
);

sub add_raw
{
	my ($self, $bytes) = @_;

	$self->_set_serialized($self->_serialized . $bytes);
	return $self;
}

signature_for add_operation => (
	method => Object,
	positional => [Str],
);

sub add_operation
{
	my ($self, $name) = @_;

	my $opcode = Bitcoin::Crypto::Script::Opcode->get_opcode_by_name($name);
	$self->add_raw($opcode->code);

	return $self;
}

sub add
{
	goto \&add_operation;
}

signature_for push_bytes => (
	method => Object,
	positional => [ByteStr],
);

sub push_bytes
{
	my ($self, $bytes) = @_;

	my $len = length $bytes;
	Bitcoin::Crypto::Exception::ScriptPush->raise(
		'empty push_bytes data argument'
	) unless $len;

	if ($len == 1 && ord($bytes) <= 0x10) {
		$self->add_operation('OP_' . ord($bytes));
	}
	elsif ($len <= 75) {
		$self
			->add_raw(pack 'C', $len)
			->add_raw($bytes);
	}
	elsif ($len < (1 << 8)) {
		$self
			->add_operation('OP_PUSHDATA1')
			->add_raw(pack 'C', $len)
			->add_raw($bytes);
	}
	elsif ($len < (1 << 16)) {
		$self
			->add_operation('OP_PUSHDATA2')
			->add_raw(pack 'v', $len)
			->add_raw($bytes);
	}
	elsif (Bitcoin::Crypto::Constants::is_32bit || $len < (1 << 32)) {
		$self
			->add_operation('OP_PUSHDATA4')
			->add_raw(pack 'V', $len)
			->add_raw($bytes);
	}
	else {
		Bitcoin::Crypto::Exception::ScriptPush->raise(
			'too much data to push onto stack in one operation'
		);
	}

	return $self;
}

sub push
{
	goto \&push_bytes;
}

# this can only detect native segwit in this context, as P2SH outputs are
# indistinguishable from any other P2SH
signature_for is_native_segwit => (
	method => Object,
	positional => [],
);

sub is_native_segwit
{
	my ($self) = @_;
	my @segwit_types = qw(P2WPKH P2WSH);

	my $script_type = $self->type // '';

	return 0 != grep { $script_type eq $_ } @segwit_types;
}

signature_for get_script => (
	method => Object,
	positional => [],
);

sub get_script
{
	my ($self) = @_;

	return $self->_serialized;
}

signature_for get_hash => (
	method => Object,
	positional => [],
);

sub get_hash
{
	my ($self) = @_;
	return hash160($self->_serialized);
}

sub get_script_hash
{
	carp_once "Bitcoin::Crypto::Script->get_script_hash is deprecated. Use Bitcoin::Crypto::Script->get_hash instead.";
	goto \&get_hash;
}

signature_for to_serialized => (
	method => Object,
	positional => [],
);

sub to_serialized
{
	my ($self) = @_;

	return $self->_serialized;
}

signature_for from_serialized => (
	method => Str,
	positional => [Any],

	# no need to validate ByteStr, as it will be passed to add_raw
);

sub from_serialized
{
	my ($class, $bytes) = @_;

	return $class->new->add_raw($bytes);
}

signature_for from_standard => (
	method => Str,
	positional => [ScriptDesc, {slurpy => 1}],
);

sub from_standard
{
	my ($class, $desc) = @_;

	return $class->new(
		type => $desc->[0],
		address => $desc->[1],
	);
}

signature_for run => (
	method => Object,
	positional => [HashRef, {slurpy => 1}],
);

sub run
{
	my ($self, $runner_args) = @_;

	my $runner = Bitcoin::Crypto::Script::Runner->new($runner_args);
	return $runner->execute($self)->stack;
}

signature_for witness_program => (
	method => Object,
	positional => [],
);

sub witness_program
{
	my ($self) = @_;

	my $program = Bitcoin::Crypto::Script->new(network => $self->network);
	$program
		->add_operation('OP_' . Bitcoin::Crypto::Constants::segwit_witness_version)
		->push_bytes(sha256($self->get_script));

	return $program;
}

signature_for get_legacy_address => (
	method => Object,
	positional => [],
);

sub get_legacy_address
{
	my ($self) = @_;
	return encode_base58check($self->network->p2sh_byte . $self->get_hash);
}

signature_for get_compat_address => (
	method => Object,
	positional => [],
);

sub get_compat_address
{
	my ($self) = @_;

	# network field is not required, lazy check for completeness
	Bitcoin::Crypto::Exception::NetworkConfig->raise(
		'this network does not support segregated witness'
	) unless $self->network->supports_segwit;

	return $self->witness_program->get_legacy_address;
}

signature_for get_segwit_address => (
	method => Object,
	positional => [],
);

sub get_segwit_address
{
	my ($self) = @_;

	# network field is not required, lazy check for completeness
	Bitcoin::Crypto::Exception::NetworkConfig->raise(
		'this network does not support segregated witness'
	) unless $self->network->supports_segwit;

	return encode_segwit($self->network->segwit_hrp, join '', @{$self->witness_program->run});
}

signature_for has_type => (
	method => Object,
	positional => [],
);

sub has_type
{
	my ($self) = @_;

	return defined $self->type;
}

signature_for is_empty => (
	method => Object,
	positional => [],
);

sub is_empty
{
	my ($self) = @_;

	return length $self->_serialized == 0;
}

1;

__END__
=head1 NAME

Bitcoin::Crypto::Script - Bitcoin script instances

=head1 SYNOPSIS

	use Bitcoin::Crypto::Script;

	my $script = Bitcoin::Crypto::Script->new
		->add_operation('OP_1')
		->add_operation('OP_TRUE')
		->add_operation('OP_EQUAL');

	# getting serialized script
	my $serialized = $script->get_script();

	# getting address from script (p2wsh)
	my $address = $script->get_segwit_adress();

=head1 DESCRIPTION

This class allows you to create Perl representation of a Bitcoin script.

You can use a script object to:

=over 2

=item * create a script from opcodes

=item * serialize a script into byte string

=item * deserialize a script into a sequence of opcodes

=item * create legacy (p2sh), compat (p2sh(p2wsh)) and segwit (p2wsh) adresses

=item * execute the script

=back

=head1 METHODS

=head2 new

	$script_object = $class->new()

A constructor. Returns a new empty script instance.

See L</from_serialized> if you want to import a serialized script instead.

=head2 operations

	$ops_aref = $object->operations;

Returns an array reference of operations contained in a script:

	[
		[OP_XXX (Object), ...],
		...
	]

The first element of each subarray is the L<Bitcoin::Crypto::Script::Opcode> object. The rest of elements are
metadata and is dependant on the op type. This metadata is used during script execution.

=head2 add_operation, add

	$script_object = $object->add_operation($opcode)

Adds a new opcode at the end of a script. Returns the object instance for chaining.

C<add> is a shorter alias for C<add_operation>.

Throws an exception for unknown opcodes.

=head2 add_raw

	$script_object = $object->add_raw($bytes)

Adds C<$bytes> at the end of the script without processing them at all.

Returns the object instance for chaining.

=head2 push_bytes, push

	$script_object = $object->push_bytes($bytes)

Pushes C<$bytes> to the execution stack at the end of a script, using a minimal push opcode.

C<push> is a shorter alias for C<push_bytes>.

For example, running C<< $script->push_bytes("\x03") >> will have the same effect as C<< $script->add_operation('OP_3') >>.

Throws an exception for data exceeding a 4 byte number in length.

Note that no data longer than 520 bytes can be pushed onto the stack in one operation, but this method will not check for that.

Returns the object instance for chaining.

=head2 to_serialized

	$bytestring = $object->get_script()

Returns a serialized script as byte string.

=head2 from_serialized

	$script = Bitcoin::Crypto::Script->from_serialized($bytestring);

Creates a new script instance from a bytestring.

=head2 get_script

Same as L</to_serialized>.

=head2 get_hash

	$bytestring = $object->get_hash()

Returns a serialized script parsed with C<HASH160> (ripemd160 of sha256).

=head2 set_network

	$script_object = $object->set_network($val)

Change key's network state to C<$val>. It can be either network name present in L<Bitcoin::Crypto::Network> package or an instance of this class.

Returns current object instance.

=head2 get_legacy_address

	$address = $object->get_legacy_address()

Returns string containing Base58Check encoded script hash (p2sh address)

=head2 get_compat_address

	$address = $object->get_compat_address()

Returns string containing Base58Check encoded script hash containing a witness program for compatibility purposes (p2sh(p2wsh) address)

=head2 get_segwit_address

	$address = $object->get_segwit_address()

Returns string containing Bech32 encoded witness program (p2wsh address)

=head2 run

	my $result_stack = $object->run()

Executes the script and returns the resulting script stack.

This is a convenience method which constructs runner instance in the
background. This helper is only meant to run simple scripts.

=head1 EXCEPTIONS

This module throws an instance of L<Bitcoin::Crypto::Exception> if it encounters an error. It can produce the following error types from the L<Bitcoin::Crypto::Exception> namespace:

=over 2

=item * ScriptOpcode - unknown opcode was specified

=item * ScriptPush - data pushed to the execution stack is invalid

=item * ScriptSyntax - script syntax is invalid

=item * ScriptRuntime - script runtime error

=item * NetworkConfig - incomplete or corrupted network configuration

=back

=head1 SEE ALSO

=over 2

=item L<Bitcoin::Crypto::Script::Runner>

=item L<Bitcoin::Crypto::Script::Opcode>

=item L<Bitcoin::Crypto::Network>

=back

=cut

