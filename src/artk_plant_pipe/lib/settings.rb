# frozen_string_literal: true

require 'json'
require_relative 'catalog'
require_relative 'services'
require_relative 'fittings_data'
require_relative 'supports'

module ArtK
  module PlantPipe
    # Current drawing settings with validation. Pure Ruby; persistence is
    # injected (SketchUp defaults in the extension, a Hash in tests).
    module Settings
      DEFAULTS = {
        'service'       => 'CW',
        'catalog'       => 'PVC_TIS17',
        'size'          => '1"',
        'rating'        => 'Class 13.5',
        'insulation_mm' => 0,
        'slope_pct'     => 1.04,
        'elbow_type'    => 'lr',    # lr | sr
        'elevation_ref' => 'cl',    # cl = centreline | bop = bottom of pipe
        'segments'      => 16,      # circle segments of the pipe section
        'snap45'        => true,    # snap plan directions to 45° increments
        'centerline'    => true,    # keep centreline edges on their own tag
        'labels'        => false,   # add line-number text labels
        'color_scheme'  => 'material',
        'pipe_color'    => '',      # '#rrggbb' = the user's own colour for new / rebuilt runs
        'lod'           => 'detailed', # detailed | light
        'support_type'  => 'clevis',
        'support_group_mm' => 600.0, # neighbouring pipes within this clear gap share a support (0 = off)
        'waste_pct'     => 5.0,
        'valve_type'    => 'gate',
        'hdpe_joint'    => 'auto'     # auto (by size) | butt | ef | comp – HDPE fitting system
      }.freeze

      module_function

      # Returns a clean settings hash, fixing any inconsistent combination
      # (e.g. a size that does not exist in the chosen catalogue).
      def sanitize(input)
        s = DEFAULTS.merge(stringify(input || {}))
        s['service'] = DEFAULTS['service'] unless Services.codes.include?(s['service'])
        s['catalog'] = Services.get(s['service'])[:catalog] unless Catalog.keys.include?(s['catalog'])
        sizes = Catalog.sizes(s['catalog'])
        s['size'] = sizes.include?(s['size']) ? s['size'] : closest_size(s['catalog'], s['size'])
        ratings = Catalog.ratings(s['catalog'], s['size'])
        s['rating'] = Catalog.get(s['catalog'])[:default_rating] unless ratings.include?(s['rating'])
        s['rating'] = ratings.first unless ratings.include?(s['rating'])
        s['insulation_mm'] = clamp(s['insulation_mm'].to_f, 0.0, 200.0)
        s['slope_pct'] = clamp(s['slope_pct'].to_f, 0.0, 10.0)
        s['elbow_type'] = %w[lr sr].include?(s['elbow_type']) ? s['elbow_type'] : 'lr'
        s['elevation_ref'] = %w[cl bop].include?(s['elevation_ref']) ? s['elevation_ref'] : 'cl'
        s['segments'] = clamp(s['segments'].to_i, 8, 48)
        s['segments'] += 1 if s['segments'].odd? # even count keeps sections symmetric
        %w[snap45 centerline labels].each { |k| s[k] = truthy(s[k]) }
        s['color_scheme'] = Services::SCHEMES.key?(s['color_scheme']) ? s['color_scheme'] : 'material'
        s['pipe_color'] = s['pipe_color'].to_s.downcase.match?(/\A#\h{6}\z/) ? s['pipe_color'].to_s.downcase : ''
        s['lod'] = %w[detailed light].include?(s['lod']) ? s['lod'] : 'detailed'
        s['support_type'] = 'clevis' unless Supports::TYPES.key?(s['support_type'])
        s['waste_pct'] = clamp(s['waste_pct'].to_f, 0.0, 50.0)
        s['support_group_mm'] = clamp(s['support_group_mm'].to_f, 0.0, 1500.0)
        s['valve_type'] = 'gate' unless FittingsData::VALVES.key?(s['valve_type'])
        s['hdpe_joint'] = 'auto' unless %w[auto butt ef comp].include?(s['hdpe_joint'].to_s)
        s.select { |k, _| DEFAULTS.key?(k) }
      end

      # [r, g, b] of a '#rrggbb' colour, or nil.
      def rgb(hex)
        return nil unless hex.to_s.match?(/\A#\h{6}\z/)

        [1, 3, 5].map { |i| hex[i, 2].to_i(16) }
      end

      def spec(settings)
        Catalog.spec(settings['catalog'], settings['size'], settings['rating'])
      end

      # Pick the catalogue size whose OD is closest to the requested one,
      # so switching material keeps roughly the same pipe.
      def closest_size(catalog, wanted)
        cat = Catalog.get(catalog)
        target = cat[:sizes].find { |z| z[:size] == wanted }
        target_od = target ? target[:od] : guess_od(wanted)
        return cat[:sizes].first[:size] unless target_od

        cat[:sizes].min_by { |z| (z[:od] - target_od).abs }[:size]
      end

      def guess_od(size)
        Catalog.all.each_value do |c|
          z = c[:sizes].find { |x| x[:size] == size }
          return z[:od] if z
        end
        nil
      end

      def load(json)
        sanitize(json && !json.empty? ? JSON.parse(json) : {})
      rescue JSON::ParserError
        sanitize({})
      end

      def dump(settings)
        JSON.generate(sanitize(settings))
      end

      def stringify(h)
        h.each_with_object({}) { |(k, v), o| o[k.to_s] = v }
      end

      def clamp(v, lo, hi)
        [[v, lo].max, hi].min
      end

      def truthy(v)
        v == true || v.to_s == 'true' || v.to_s == '1'
      end
    end
  end
end
