class PromptsController < ApplicationController

  def prompt
    handler = PromptService.new.call(prompt: params[:prompt])
    prompt_keys = PromptService::MANDATORY_PROMPTS + PromptService::OPTIONAL_PROMPTS
    current_prompts = JSON.parse(REDIS.get(session.id || 'test')).select do |k, _|
      prompt_keys.include?(k)
    end

    current_prompts[:message] = handler.success[:message].first
    if handler.success?
      render json: current_prompts, status: :ok
    else
      render json: { message: handler.failure[:message] }, status: :unprocessable_entity
    end
  end

  private

  def search_params
    params.permit(:prompt)
  end
end
