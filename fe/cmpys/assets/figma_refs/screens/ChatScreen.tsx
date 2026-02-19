import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChatBubble } from '../ChatBubble';
import { ChevronLeft, Send } from 'lucide-react';

interface ChatScreenProps {
  onBack: () => void;
}

const initialMessages = [
  {
    sender: 'idol' as const,
    message: "Hey! I'm an AI simulation of Elon. What would you like to know about my journey?",
    timestamp: '10:30 AM',
  },
  {
    sender: 'user' as const,
    message: 'How did you overcome fear when starting SpaceX?',
    timestamp: '10:32 AM',
  },
  {
    sender: 'idol' as const,
    message: "Fear is natural, but I focused on the mission rather than the risk. When you believe in something deeply enough, fear becomes secondary to purpose.",
    timestamp: '10:33 AM',
  },
];

export function ChatScreen({ onBack }: ChatScreenProps) {
  const [messages] = useState(initialMessages);
  const [inputValue, setInputValue] = useState('');

  return (
    <div className="h-screen bg-[#121212] flex flex-col">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="px-6 pt-12 pb-4 border-b border-[#2A2A2E] bg-[#121212]"
      >
        <motion.button
          whileHover={{ scale: 1.1 }}
          whileTap={{ scale: 0.9 }}
          onClick={onBack}
          className="p-2 -ml-2 mb-4"
        >
          <ChevronLeft className="w-6 h-6 text-white" />
        </motion.button>
        <div className="flex items-center gap-3">
          <motion.div
            animate={{
              scale: [1, 1.05, 1],
            }}
            transition={{
              type: "tween",
              duration: 2,
              repeat: Infinity,
              ease: "easeInOut",
            }}
            className="w-10 h-10 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center"
          >
            <span className="text-white text-sm">EM</span>
          </motion.div>
          <div>
            <h2 className="text-white">Elon Musk</h2>
            <span className="text-xs text-[#A1A1AA] bg-[#1C1C1E] px-2 py-0.5 rounded-full border border-[#2A2A2E]">
              AI Simulation
            </span>
          </div>
        </div>
      </motion.div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-6 py-6 pb-24">
        <AnimatePresence>
          {messages.map((msg, idx) => (
            <motion.div
              key={idx}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: idx * 0.2, duration: 0.4 }}
            >
              <ChatBubble {...msg} />
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      {/* Input */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="absolute bottom-0 left-0 right-0 px-6 py-4 pb-24 border-t border-[#2A2A2E] bg-[#121212]/95 backdrop-blur-lg"
      >
        <div className="flex items-center gap-3 bg-[#1C1C1E] rounded-[24px] px-4 py-3 border border-[#2A2A2E]">
          <input
            type="text"
            placeholder="Type a message..."
            value={inputValue}
            onChange={(e) => setInputValue(e.target.value)}
            className="flex-1 bg-transparent text-white placeholder-[#A1A1AA] outline-none"
          />
          <motion.button
            whileHover={{ scale: 1.1, rotate: 15 }}
            whileTap={{ scale: 0.9 }}
            className="w-8 h-8 rounded-full bg-[#7B61FF] flex items-center justify-center flex-shrink-0"
          >
            <Send className="w-4 h-4 text-white" />
          </motion.button>
        </div>
      </motion.div>
    </div>
  );
}