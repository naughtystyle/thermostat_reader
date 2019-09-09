class Stats < ApplicationRecord
  READING_TYPES = %i(
    temperature
    humidity
    battery_charge
  ).freeze

  STATISTIC_TYPES = %w(
    average
    maximum
    minimum
  ).freeze

  self.primary_key = :thermostat_id

  def self.define_reading_types
    READING_TYPES.each do |reading_type|
      define_method("persisted_#{reading_type}") do
        build_stats_for(reading_type)
      end
    end
  end

  def temperature
    current_stats_for("temperature")
  end

  def humidity
    current_stats_for("humidity")
  end

  def battery_charge
    current_stats_for("battery_charge")
  end

  def readonly?
    true
  end

  define_reading_types

  private

  def build_stats_for(reading_type)
    Stats.
      find_by!(thermostat_id: id, stats_type: reading_type).
      attributes.slice(*STATISTIC_TYPES)
  end

  def current_stats_for(reading_type)
    {
      "average" => recalculate_average(reading_type),
      "maximum" => [send("persisted_#{reading_type}")["maximum"], *fetcher(reading_type)].max,
      "minimum" => [send("persisted_#{reading_type}")["minimum"], *fetcher(reading_type)].min
    }
  end

  def recalculate_average(reading_type)
    current_average = send("persisted_#{reading_type}")["average"]
    return current_average if synchronized?
    total_readings_count = thermostat.reload.readings_count
    persisted_readings_count = total_readings_count - readings_in_queue.size
    new_reading_sum = Array(fetcher(reading_type)).sum

    (((current_average * persisted_readings_count) + new_reading_sum) / total_readings_count).to_f.round(2)
  end

  def fetcher(reading_type)
    ReadingJobFetcher.new(*readings_in_queue.to_a).fetch.map(&reading_type.to_sym) rescue []
  end

  def synchronized?
    readings_in_queue.size.zero?
  end

  def readings_in_queue
    Range.new(
      thermostat.reload.readings.order(:created_at).last.tracking_number,
      thermostat.reload.readings_count, true
    )
  end

  def thermostat
    Thermostat.find(id)
  end

  private_constant :READING_TYPES, :STATISTIC_TYPES
end
