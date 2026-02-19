import React from 'react';

interface ChatBubbleProps {
  message: string;
  sender: 'user' | 'idol';
  timestamp?: string;
}

export function ChatBubble({ message, sender, timestamp }: ChatBubbleProps) {
  const isUser = sender === 'user';

  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'} mb-4`}>
      <div className={`max-w-[80%] space-y-1`}>
        <div
          className={`px-4 py-3 rounded-[20px] ${
            isUser
              ? 'bg-[#7B61FF] text-white rounded-br-md'
              : 'bg-[#1C1C1E] text-white border border-[#2A2A2E] rounded-bl-md'
          }`}
        >
          <p>{message}</p>
        </div>
        {timestamp && (
          <p className={`text-xs text-[#A1A1AA] ${isUser ? 'text-right' : 'text-left'}`}>
            {timestamp}
          </p>
        )}
      </div>
    </div>
  );
}
