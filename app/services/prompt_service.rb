# frozen_string_literal: true

require "dry/transaction"
require "json"

class PromptService
  include Dry::Transaction
  MANDATORY_PROMPTS = %w[origin destination season family_size trip_days].freeze
  OPTIONAL_PROMPTS = %w[price hotel_rating].freeze

  step :build_prompt
  step :build_trips_response
  step :fetch_images
  step :result

  private

  def build_prompt(input)
    context = REDIS.get(input[:user_session])
    context = context.blank? ? {} : JSON.parse(context)
    @client = OpenAI::Client.new
    response = @client.chat(
      parameters: {
        model: 'gpt-4o',
        messages: [
          {
            role: 'user',
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
        model: 'gpt-4o',
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'user',
            content: "
            Task:
            - Always respond with an array of JSON objects;
              - Follow the format { trip_plans: [...] };
              - Every Image key should have a null value;
            - When given a country, create 2 Trip Plans;
              - The destination should be different cities or counties of the country;
            - When given a city or county, create 1 Trip Plan;
            - The current year is #{Time.zone.now.utc.year};
            - When returning dates, always use the format 'day/month/year';
            - Required information
              - Destination (destination);
              - Origin (origin);
              - Family Size (family_size);
              - A list with 3 Hotels (hotels);
                - Follow the format { name: ...,  image: ... };
              - Average temperature (average_temp)
              - A list with 3 surrounding cities (surrounding_cities);
              - A list with 3 Landmarks (landmarks);
                - Follow the format { name: ..., description: ..., image: ... };
                - Description should be 10 words;
              - Popular restaurants (restaurants);
                - Follow the format { name: ..., image: ... };
              - Small history of the area (small_history);
              - 10 word description of the area (short_description);
              - Start Date (start_date);
              - End Date (end_date);
              - Estimated price in Euros; (price)
                - Include the currency icon in the end of the price;
              - A list of 3 planes to board to the destination with an hour and travel time (departures_from_origin);
                - Follow the format 'date, departure hour, duration'
              - A list of 3 planes to board to the origin with an hour and travel time (departures_from_destination);
                - Follow the format 'date, departure hour, duration'
              - Activities for each day, for each time of day, based on the family size (activities_per_day);
                - Follow the format { morning: ..., afternoon: ..., evening: ... }
                - Each key should be the specific day of the trip;
                - Return each activity as a string;
                - The first activity needs to match the Arrival to the destination (use the first string from departures_from_origin);
                - The last activity needs to match the Departure of the destination (use the first string from departures_from_destination);
              - Image;
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
    input[:ai_message] = JSON.parse(response['choices'].first['message']['content'])
    Success(input)
  rescue StandardError => e
    Failure(message: "Error getting information! #{e}")
  end

  def fetch_images(input)
    url = URI('https://google.serper.dev/images')
    @https = Net::HTTP.new(url.host, url.port)
    @https.use_ssl = true
    @request = Net::HTTP::Post.new(url)
    @request['X-API-KEY'] = ENV.fetch('SERPER_API_KEY')
    @request['Content-Type'] = 'application/json'

    input[:ai_message]['trip_plans'].each do |trip_plan|
      ['image', 'hotels', 'landmarks', 'restaurants'].each do |key|
        if key == 'image'
          trip_plan[key] = serper_request("wikipedia city #{trip_plan['destination']}") # To get barcelona the city and not the club for example
        else
          trip_plan[key].each { |row| row['image'] = serper_request("#{trip_plan['destination']} #{key} #{row['name']}") }
        end
      end
    end
    Success(input)
  end

  def result(input)
    Success(message: input[:ai_message] || '...')
  end

  private

  def serper_request(query)
    @request.body = JSON.dump({ 'q': query })
    response = JSON.parse(@https.request(@request).read_body)
    response['images'].find { |hash| hash['imageWidth'] >= 200 && hash['imageHeight'] >= 200 }['imageUrl']
  end
end
