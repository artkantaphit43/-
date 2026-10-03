# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Version of the data the extension stores in a model (attribute
    # dictionary "ArtK_PlantPipe" on runs and placed library parts).
    #
    # Rules, so that drawings made with any older version keep working:
    #   * never rename or remove a stored key, and never change what an
    #     existing key means – add new keys with a default instead
    #     (Settings.sanitize fills missing settings);
    #   * when a change cannot follow that rule, raise CURRENT and add a
    #     step that converts records of the previous format. Steps are never
    #     edited once released; old files run through every step in order.
    #   * a step may set rec['rebuild'] = true to have the run's geometry
    #     regenerated after the upgrade.
    # Stored keys are listed in docs/DATA_FORMAT.md.
    module DataFormat
      CURRENT = 2

      # format => step converting a record of that format to the next one
      STEPS = {
        # 1 = v1.0–v1.6 (no stamp) → 2 = v1.7: same keys, stamp only
        1 => ->(rec) { rec }
      }.freeze

      KEY = 'fmt'

      module_function

      def version(rec)
        (rec[KEY] || 1).to_i
      end

      # [record, :current | :upgraded | :newer]. A record written by a
      # newer version is returned untouched.
      def upgrade(rec)
        v = version(rec)
        return [rec, :newer] if v > CURRENT
        return [rec, :current] if v == CURRENT

        out = rec.dup
        (v...CURRENT).each { |n| out = STEPS.fetch(n).call(out) }
        out[KEY] = CURRENT
        [out, :upgraded]
      end
    end
  end
end
