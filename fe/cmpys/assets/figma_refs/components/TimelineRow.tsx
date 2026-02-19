import React, { useState } from 'react';
import { motion } from 'motion/react';
import { TagChip } from './TagChip';
import { ChevronRight } from 'lucide-react';
import { EvidenceSheet } from './EvidenceSheet';

interface TimelineRowProps {
  age: number;
  achievement: string;
  category: string;
  description?: string;
  confidence?: 'high' | 'medium' | 'low';
  datePrecision?: 'exact' | 'year';
  onEvidenceClick?: () => void;
  onOpenEvidence?: () => void;
}

const confidenceConfig = {
  high: {
    label: 'High',
    bg: 'bg-[#4ADE80]/10',
    text: 'text-[#4ADE80]',
    border: 'border-[#4ADE80]/30',
  },
  medium: {
    label: 'Med',
    bg: 'bg-[#FBBF24]/10',
    text: 'text-[#FBBF24]',
    border: 'border-[#FBBF24]/30',
  },
  low: {
    label: 'Low',
    bg: 'bg-[#F87171]/10',
    text: 'text-[#F87171]',
    border: 'border-[#F87171]/30',
  },
};

const datePrecisionConfig = {
  exact: {
    label: 'Exact',
    bg: 'bg-[#7B61FF]/10',
    text: 'text-[#7B61FF]',
    border: 'border-[#7B61FF]/30',
  },
  year: {
    label: 'Year',
    bg: 'bg-[#A1A1AA]/10',
    text: 'text-[#A1A1AA]',
    border: 'border-[#A1A1AA]/30',
  },
};

export function TimelineRow({
  age,
  achievement,
  category,
  description,
  confidence = 'high',
  datePrecision = 'year',
  onEvidenceClick,
  onOpenEvidence,
}: TimelineRowProps) {
  const [isPressed, setIsPressed] = useState(false);

  const confidenceStyle = confidenceConfig[confidence];
  const precisionStyle = datePrecisionConfig[datePrecision];

  return (
    <motion.div
      whileHover={{ scale: 1.02, x: 4 }}
      whileTap={{ scale: 0.98 }}
      onTapStart={() => setIsPressed(true)}
      onTap={() => {
        setIsPressed(false);
        if (onEvidenceClick) {
          onEvidenceClick();
        }
        if (onOpenEvidence) {
          onOpenEvidence();
        }
      }}
      onTapCancel={() => setIsPressed(false)}
      className={`bg-[#1C1C1E] rounded-[20px] p-4 border transition-all cursor-pointer ${
        isPressed
          ? 'border-[#7B61FF] shadow-lg shadow-[#7B61FF]/20'
          : 'border-[#2A2A2E] hover:border-[#7B61FF]/30'
      }`}
    >
      <div className="space-y-3">
        {/* Header with Age and Category */}
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-center gap-2 flex-1 min-w-0">
            <div className="w-8 h-8 rounded-full bg-[#7B61FF]/20 flex items-center justify-center text-[#7B61FF] flex-shrink-0 shadow-sm">
              <span className="text-sm font-medium">{age}</span>
            </div>
            <TagChip label={category} variant="category" className="text-xs px-3 py-1" />
          </div>

          {/* Right-side Badges */}
          <div className="flex flex-col gap-1.5 items-end flex-shrink-0">
            {/* Confidence Badge */}
            <div
              className={`px-2 py-0.5 rounded-full text-[10px] font-medium border ${confidenceStyle.bg} ${confidenceStyle.text} ${confidenceStyle.border}`}
            >
              {confidenceStyle.label}
            </div>

            {/* Date Precision Badge */}
            <div
              className={`px-2 py-0.5 rounded-full text-[10px] font-medium border ${precisionStyle.bg} ${precisionStyle.text} ${precisionStyle.border}`}
            >
              {precisionStyle.label}
            </div>
          </div>
        </div>

        {/* Achievement Title */}
        <h4 className="text-white leading-snug">{achievement}</h4>

        {/* Description */}
        {description && (
          <p className="text-[#A1A1AA] text-sm leading-relaxed">{description}</p>
        )}

        {/* Evidence Link */}
        <motion.div
          initial={{ opacity: 0, y: 5 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="pt-2 border-t border-[#2A2A2E]"
        >
          <div className="flex items-center justify-between">
            <span className="text-[#7B61FF] text-sm font-medium">View evidence</span>
            <motion.div
              animate={{ x: isPressed ? 4 : 0 }}
              transition={{ duration: 0.2 }}
            >
              <ChevronRight className="w-4 h-4 text-[#7B61FF]" />
            </motion.div>
          </div>
        </motion.div>

        {/* Pressed State Indicator (for demo purposes) */}
        {isPressed && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="pt-2 border-t border-[#7B61FF]/30"
          >
            <p className="text-[#7B61FF] text-xs italic">
              ↑ Tap opens EvidenceSheet bottom sheet
            </p>
          </motion.div>
        )}
      </div>
    </motion.div>
  );
}