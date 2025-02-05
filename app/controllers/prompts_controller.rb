class PromptsController < ApplicationController

  def prompt
    handler = PromptService.new.call(params)

    if handler.success?
      render json: handler.success[:message], status: :ok
    else
      render json: { message: handler.success[:message] }, status: :unprocessable_entity
    end
  end

  private

  def search_params
    params.permit(:prompt, :user_session)
  end
end
