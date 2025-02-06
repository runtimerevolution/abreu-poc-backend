# frozen_string_literal: true

require "dry/transaction"
require "json"

class PromptService
  include Dry::Transaction
  MANDATORY_PROMPTS = %w[origin destination season family_size trip_days].freeze
  OPTIONAL_PROMPTS = %w[price hotel_rating].freeze

  step :build_prompt
  step :build_trips_response
  step :result

  private

  def build_prompt(input)
    context = REDIS.get(input[:user_session])
    context = context.blank? ? {} : JSON.parse(context)
    @client = OpenAI::Client.new
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: "
            Task:
            - Extract topics from the request;
            - Return the response in a single JSON Object and it should not have nested JSON objects;
            - Try to extract at least the following keys with the default value of null: #{(MANDATORY_PROMPTS + OPTIONAL_PROMPTS).join(', ')};
            - The 'destination' topic MUST either be a country, county or city. If its none of them, leave the value as null;
            - Add more topics if there are more and give them a relevant name;
            - Example structure: { 'topic': 'value' };
            - Break it down as much as possible;
            Params:
            #{ input[:prompt] }
            "
          }
        ],
        temperature: 0.7
      }
    )
    prompt_data = JSON.parse(
      response['choices'].first['message']['content'].match(/\s*\{.*?\}\s*/m)[0]
    ).delete_if { |k, v| v.blank? }
    context.merge!(prompt_data) { |k, old_v, new_v| new_v.present? ? new_v : old_v }

    REDIS.set(input[:user_session], context.to_json)
    input[:clean_prompts] = context.map { |k, v| "#{k}: #{v};\n" if v.present? }.compact.join

    Success(input)
  end

  def build_trips_response(input)
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        messages: [
          {
            role: "user",
            content: "
            Task:
            - Always respond with an array of JSON
            - When given a country, create 2 Trip Plans with the following information:
              - Destination (destination);
              - Hotel List (hotel_list);
              - Average temperature (average_temp)
              - Surrounding cities (surrounding_cities);
              - Landmarks (landmarks);
              - Popular restaurants (restaurants);
              - Small history of the area (small_history);
              - 10 word description of the area (short_description);
              - Estimated price; (price)
              - An example of a plane to board to the destination with an hour and travel time (departure_from_origin);
              - An example of a plane to board to the origin with an hour and travel time (departure_from_destination);
              - Activities for each day, for each time of day (activities_per_day);
                - Follow the format { morning: ..., afternoon: ..., evening: ... }
                - Each key should be the specific day of the trip;
                - Return each activity as a string;
                - The first activity needs to match the Arrival to the destination;
                - The last activity needs to match the Departure of the destination;
            - When given a city or county, create 1 Trip Plan with the following information:
              - Destination (destination);
              - Hotel List (hotel_list);
              - Average temperature (average_temp)
              - Surrounding cities (surrounding_cities);
              - Landmarks (landmarks);
              - Popular restaurants (restaurants);
              - Small history of the area (small_history);
              - 10 word description of the area (short_description);
              - Estimated price; (price)
              - An example of a plane to board to the destination with an hour and travel time (departure_from_origin);
              - An example of a plane to board to the origin with an hour and travel time (departure_from_destination);
              - Activities for each day, for each time of day (activities_per_day);
                - Follow the format { morning: ..., afternoon: ..., evening: ... }
                - Each key should be the specific day of the trip;
                - Return each activity as a string;
                - The first activity needs to match the Arrival to the destination;
                - The last activity needs to match the Departure of the destination;
            - Remove values that are not specified or provided.
            - Return the information in portuguese of Portugal.
            - Remove all single quote from response.
            Params:
            #{ input[:prompt] };
            #{ input[:clean_prompts] };
            Style: Expository;
            Tone: Professional;
            "
          }
        ],
        temperature: 0.7
      }
    )
    input[:ai_message] = JSON.parse(response['choices'].first['message']['content'].match(/\[\s*\{.*?\}\s*\]/m)[0])
    Success(input)
  rescue StandardError => e
    Failure(message: "Error getting information! #{e}")
  end

  def result(input)
    Success(message: input[:ai_message] || "...")
  end
end
