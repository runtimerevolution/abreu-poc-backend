# frozen_string_literal: true

require "dry/transaction"
require "json"

class QuestionsService
  include Dry::Transaction

  step :build_questions
  step :result

  private

  def build_questions
    client = OpenAI::Client.new
    response = client.chat(
      parameters: {
        model: 'gpt-4o',
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'user',
            content: "
            Task:
            - Give me seven questions that can help me pinpoint a vacation plan;
            - Return the questions in an array of JSON objects;
              - Format: { questions: [...] }
              - Make sure to always ask where the user wants to go;
              - Question object format: { question: ..., key: ... };
              - The key value should be in english;
            - Don't ask for suggestions
            - Remove values that are not specified or provided.
            - Return the information in portuguese of Portugal.
            - Remove all single quote from response.
            Style: Expository;
            Tone: Professional;
            "
          }
        ],
        temperature: 0.7
      }
    )
    Success({ questions: JSON.parse(response['choices'].first['message']['content']) })
  rescue StandardError => e
    Failure(message: "Error getting information! #{e}")
  end

  def result(input)
    Success(message: input[:questions] || '...')
  end
end
