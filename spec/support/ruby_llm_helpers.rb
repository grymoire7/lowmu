module RubyLlmHelpers
  def mock_llm_response(content:)
    mock_response = instance_double(RubyLLM::Message, content: content)
    mock_chat = instance_double(RubyLLM::Chat, ask: mock_response)
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    mock_chat
  end
end

RSpec.configure do |config|
  config.include RubyLlmHelpers
end
