import React from 'react';
import { motion } from 'motion/react';
import { Check } from 'lucide-react';

interface IdolCandidateCardProps {
  name: string;
  description: string;
  birthDate: string;
  confidence: number;
  provider: string;
  avatarUrl?: string;
  selected?: boolean;
  onClick?: () => void;
}

export function IdolCandidateCard({
  name,
  description,
  birthDate,
  confidence,
  provider,
  avatarUrl,
  selected = false,
  onClick,
}: IdolCandidateCardProps) {
  return (
    <motion.button
      onClick={onClick}
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      className={`w-full bg-[#1C1C1E] rounded-[20px] p-4 border transition-all ${
        selected ? 'border-[#7B61FF]' : 'border-[#2A2A2E]'
      } shadow-lg shadow-black/20`}
    >
      <div className="flex gap-4">
        {/* Avatar */}
        <div className="relative flex-shrink-0">
          <div className="w-14 h-14 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center overflow-hidden">
            {avatarUrl ? (
              <img src={avatarUrl} alt={name} className="w-full h-full object-cover" />
            ) : (
              <span className="text-white text-lg">
                {name
                  .split(' ')
                  .map((n) => n[0])
                  .join('')
                  .substring(0, 2)
                  .toUpperCase()}
              </span>
            )}
          </div>
          {selected && (
            <motion.div
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              className="absolute -bottom-1 -right-1 w-6 h-6 rounded-full bg-[#7B61FF] border-2 border-[#1C1C1E] flex items-center justify-center"
            >
              <Check className="w-3 h-3 text-white" />
            </motion.div>
          )}
        </div>

        {/* Content */}
        <div className="flex-1 min-w-0 text-left">
          <div className="flex items-start justify-between gap-2 mb-1">
            <h3 className="text-white font-medium truncate">{name}</h3>
            <motion.div
              animate={selected ? { scale: [1, 1.1, 1] } : {}}
              transition={{
                type: 'tween',
                duration: 0.3,
                ease: 'easeInOut',
              }}
              className="flex-shrink-0 px-2 py-1 rounded-full bg-[#7B61FF]/20 border border-[#7B61FF]/30"
            >
              <span className="text-[#7B61FF] text-xs font-medium">{confidence}%</span>
            </motion.div>
          </div>
          
          <p className="text-[#A1A1AA] text-sm mb-2 line-clamp-1">{description}</p>
          
          <div className="flex items-center justify-between">
            <span className="text-[#A1A1AA] text-xs">Born {birthDate}</span>
            <span className="text-[#7B61FF] text-xs px-2 py-0.5 rounded-full bg-[#7B61FF]/10 border border-[#7B61FF]/20">
              {provider}
            </span>
          </div>
        </div>
      </div>
    </motion.button>
  );
}
