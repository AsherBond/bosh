require 'ipaddr'

module Bosh
  module Director
    class IpAddrOrCidr
      include Comparable

      delegate :==, :include?, :ipv4?, :ipv6?, :netmask, :mask, :to_i, :to_range, :prefix, :succ, :<=>, to: :@ipaddr

      def initialize(ip_or_cidr)
        @ipaddr =
          if ip_or_cidr.kind_of?(IpAddrOrCidr)
            IPAddr.new(ip_or_cidr.to_s)
          elsif ip_or_cidr.kind_of?(Integer)
            IPAddr.new(ip_or_cidr, inet_type_for(ip_or_cidr))
          else
            begin
              IPAddr.new(ip_or_cidr)
            rescue IPAddr::InvalidAddressError => e
              raise e, "Invalid IP or CIDR format: #{ip_or_cidr}"
            end
          end
      end

      def each_base_addr(prefix_length)
        if @ipaddr.ipv4?
          bits = 32
        elsif @ipaddr.ipv6?
          bits = 128
        end
        step_size = 2**(bits - prefix_length.to_i)
        base_addr_int = @ipaddr.to_i

        first_base_addr_int = Bosh::Director::IpAddrOrCidr.new("#{@ipaddr}/#{prefix_length}").to_i

        if base_addr_int != first_base_addr_int
          base_addr_int += step_size
        end

        while base_addr_int <= @ipaddr.to_range.last.to_i
          yield base_addr_int
          base_addr_int += step_size
        end
      end

      # Structural equality for use by +Set+ and +Hash+. Two instances are equal
      # only if they share the same base address integer, prefix length, and
      # address family. For example, +10.0.11.32/30+ and +10.0.11.32/32+ are NOT
      # equal
      #
      # @param other [Object] the object to compare with
      # @return [Boolean] +true+ if +other+ is an +IpAddrOrCidr+ with identical
      #   address, prefix, and address family; +false+ otherwise
      def eql?(other)
        other.is_a?(IpAddrOrCidr) &&
          @ipaddr.to_i == other.to_i &&
          @ipaddr.prefix == other.prefix &&
          @ipaddr.ipv4? == other.ipv4?
      end

      # Returns an integer hash value derived from the address integer, prefix
      # length, and address family - the same three fields used by {#eql?}.
      # Satisfies Ruby's contract: if +a.eql?(b)+ then +a.hash == b.hash+.
      #
      # @return [Integer] hash value for use by +Set+ and +Hash+
      def hash
        [
          @ipaddr.to_i,
          @ipaddr.prefix,
          @ipaddr.ipv4?,
        ].hash
      end

      def count
        (@ipaddr.to_range.last.to_i - @ipaddr.to_range.first.to_i) + 1
      end

      def to_s
        "#{@ipaddr}/#{@ipaddr.prefix}"
      end

      def base_addr
        @ipaddr.to_s
      end

      def to_range
        @ipaddr.to_range
      end

      def succ
        next_ip = @ipaddr.succ
        Bosh::Director::IpAddrOrCidr.new(next_ip.to_i)
      end

      def <=>(other)
        @ipaddr.to_i <=> other.to_i
      end

      def last
        Bosh::Director::IpAddrOrCidr.new(@ipaddr.to_range.last.to_i)
      end

      def first
        Bosh::Director::IpAddrOrCidr.new(@ipaddr.to_range.first.to_i)
      end

      def overlaps?(other)
        my_first = @ipaddr.to_range.first.to_i
        my_last = @ipaddr.to_range.last.to_i
        other_first = other.to_range.first.to_i
        other_last = other.to_range.last.to_i
        my_first <= other_last && other_first <= my_last
      end

      private

      def max_addresses
        ipv4? ?  IPAddr::IN4MASK : IPAddr::IN6MASK
      end

      def inet_type_for(address_int)
        address_int <= IPAddr::IN4MASK ? Socket::AF_INET : Socket::AF_INET6
      end
    end
  end
end
