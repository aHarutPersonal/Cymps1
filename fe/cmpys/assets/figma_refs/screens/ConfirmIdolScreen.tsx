import React from 'react';
import { motion } from 'motion/react';
import { ChevronLeft, AlertCircle, Calendar, Tag } from 'lucide-react';
import { PrimaryButton } from '../PrimaryButton';

interface ConfirmIdolScreenProps {
  onBack: () => void;
  onImport: () => void;
  onChooseAnother: () => void;
}

export function ConfirmIdolScreen({ onBack, onImport, onChooseAnother }: ConfirmIdolScreenProps) {
  const idolData = {
    name: 'Warren Buffett',
    bio: 'Warren Edward Buffett is an American investor, business tycoon, and philanthropist. He is currently the chairman and CEO of Berkshire Hathaway. Known as the "Oracle of Omaha", Buffett is one of the most successful investors of all time.',
    birthDate: 'August 30, 1930',
    domain: 'Finance & Investment',
    confidence: 97,
    provider: 'Wikipedia',
  };

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
        <h1 className="text-white text-2xl">Confirm idol</h1>
      </motion.div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-6 py-6">
        {/* Large Idol Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[24px] p-6 border border-[#2A2A2E] shadow-lg shadow-black/20 mb-6"
        >
          {/* Avatar */}
          <div className="flex justify-center mb-6">
            <motion.div
              animate={{
                scale: [1, 1.02, 1],
              }}
              transition={{
                type: 'tween',
                duration: 3,
                repeat: Infinity,
                ease: 'easeInOut',
              }}
              className="relative"
            >
              <div className="w-24 h-24 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center shadow-xl shadow-[#7B61FF]/20">
                <span className="text-white text-3xl font-medium">
                  {idolData.name
                    .split(' ')
                    .map((n) => n[0])
                    .join('')
                    .substring(0, 2)
                    .toUpperCase()}
                </span>
              </div>
              {/* Confidence Badge */}
              <motion.div
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                transition={{ delay: 0.3, type: 'spring', stiffness: 300, damping: 20 }}
                className="absolute -bottom-2 -right-2 px-3 py-1 rounded-full bg-[#7B61FF] border-2 border-[#1C1C1E] shadow-lg"
              >
                <span className="text-white text-xs font-medium">{idolData.confidence}% match</span>
              </motion.div>
            </motion.div>
          </div>

          {/* Name */}
          <h2 className="text-white text-2xl text-center mb-2">{idolData.name}</h2>

          {/* Domain Tag */}
          <div className="flex justify-center mb-6">
            <div className="flex items-center gap-2 px-4 py-2 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20">
              <Tag className="w-4 h-4 text-[#7B61FF]" />
              <span className="text-[#7B61FF] text-sm">{idolData.domain}</span>
            </div>
          </div>

          {/* Birth Date */}
          <div className="flex items-center justify-center gap-2 mb-6 text-[#A1A1AA]">
            <Calendar className="w-4 h-4" />
            <span className="text-sm">Born {idolData.birthDate}</span>
          </div>

          {/* Bio */}
          <div className="bg-[#121212] rounded-[20px] p-4 border border-[#2A2A2E]">
            <p className="text-[#A1A1AA] text-sm leading-relaxed">{idolData.bio}</p>
          </div>

          {/* Provider Badge */}
          <div className="flex justify-center mt-4">
            <span className="text-[#7B61FF] text-xs px-3 py-1 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20">
              Source: {idolData.provider}
            </span>
          </div>
        </motion.div>

        {/* Warning Card */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3, duration: 0.5 }}
          className="bg-[#1C1C1E] rounded-[20px] p-4 border border-[#2A2A2E] mb-6"
        >
          <div className="flex gap-3">
            <div className="flex-shrink-0">
              <div className="w-10 h-10 rounded-full bg-[#7B61FF]/10 flex items-center justify-center">
                <AlertCircle className="w-5 h-5 text-[#7B61FF]" />
              </div>
            </div>
            <div className="flex-1">
              <h3 className="text-white text-sm font-medium mb-1">Verify identity</h3>
              <p className="text-[#A1A1AA] text-sm leading-relaxed">
                Names can match multiple people. Confirm you selected the correct person before importing.
              </p>
            </div>
          </div>
        </motion.div>
      </div>

      {/* Action Buttons */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5, duration: 0.5 }}
        className="px-6 py-4 pb-8 border-t border-[#2A2A2E] bg-[#121212] space-y-3"
      >
        <PrimaryButton onClick={onImport}>Import idol</PrimaryButton>
        
        <motion.button
          onClick={onChooseAnother}
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          className="w-full px-6 py-4 rounded-[20px] bg-transparent text-[#7B61FF] border-2 border-[#7B61FF]/30 transition-all hover:border-[#7B61FF]/50 hover:bg-[#7B61FF]/5"
        >
          Choose another
        </motion.button>
      </motion.div>
    </div>
  );
}
