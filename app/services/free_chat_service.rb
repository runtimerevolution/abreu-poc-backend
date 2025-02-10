# frozen_string_literal: true

require "dry/transaction"
require "json"

class FreeChatService
  include Dry::Transaction
  MANDATORY_PROMPTS = %w[
    origin destination family_size day_of_departure day_of_return price hotel_rating main_activity
  ].freeze

  step :build_prompt
  step :build_trips_response
  step :result

  private

  def build_prompt(input)
    @last_question = REDIS.get("#{input[:user_session]}-last_reply") || 'No previous question'
    @context = REDIS.get(input[:user_session])
    @context = @context.blank? ? {} : JSON.parse(@context)
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
            - Focus on vacation related topics;
            - Return the response in a single JSON Object and it should not have nested JSON objects;
            - Try to extract at least the following keys with the default value of null: #{all_keys};
            - The 'destination' topic MUST either be a country, county or city. If its none of them, leave the value as null;
            - Add more topics if there are more and give them a relevant name;
            - Break it down as much as possible;
            Params:
            Last question you did: #{@last_question}
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
    @context.merge!(prompt_data) { |k, old_v, new_v| new_v.present? ? new_v : old_v }

    REDIS.set(input[:user_session], @context.to_json)
    input[:clean_prompts] = @context.map { |k, v| "#{k}: #{v};\n" if v.present? }.compact.join

    Success(input)
  end

  def build_trips_response(input)
    response = @client.chat(
      parameters: {
        model: "gpt-4o",
        response_format: { type: "json_object" },
        messages: [
          {
            role: "user",
            content: "
            Task:
            - Always respond with a JSON object;
            - Make a conversation with the objective of understanding where the use wants to go on vacations;
            - The questions should be around this topics: #{all_keys};
            - Take into account your last reply;
            - The JSON object must only contain a message and the value of the main topic;
            - Example structure: { 'message': ..., <main_topic_name>: <main_topic_value>, 'finished': false }
              - Topics should be in english as should be their values
              - The topic names should match one of this, but its not mandatory: #{all_keys};
              - Always show the 'finished' key despite it being false;
            - When you receive all topics in #{all_keys}, make a short resume of the trip and mark the finished as true
            - Remove values that are not specified or provided;
            - Return the information in portuguese of Portugal;
            - Remove all single quote from response;
            Params:
            Last question you did: #{@last_question}
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
    response = JSON.parse(response['choices'].first['message']['content']).delete_if { |k, v| v.blank? }
    REDIS.set("#{input[:user_session]}-last_reply", response['message'])
    @context.merge!(response.except('message', 'finished')) { |k, old_v, new_v| new_v.present? ? new_v : old_v }
    REDIS.set(input[:user_session], @context.to_json)

    input[:ai_message] = response.slice('message', 'finished')
    Success(input)
  rescue StandardError => e
    Failure(message: "Error getting information! #{e}")
  end

  def result(input)
    Success(message: input[:ai_message] || "...")
  end

  private

  def all_keys
    @all_keys ||= MANDATORY_PROMPTS.join(', ')
  end
end
