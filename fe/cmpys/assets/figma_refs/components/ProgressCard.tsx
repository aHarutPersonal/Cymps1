import React from 'react';
import { motion } from 'motion/react';

interface ProgressCardProps {
  label: string;
  progress: number;
  color?: string;
  showPercentage?: boolean;
}

export function ProgressCard({ label, progress, color = '#7B61FF', showPercentage = true }: ProgressCardProps) {
  return (
    <div className="space-y-2">
      <div className="flex justify-between items-center">
        <span className="text-white">{label}</span>
        {showPercentage && (
          <motion.span
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.3 }}
            className="text-[#A1A1AA]"
          >
            {progress}%
          </motion.span>
        )}
      </div>
      <div className="w-full h-2 bg-[#1C1C1E] rounded-full overflow-hidden">
        <motion.div
          initial={{ width: 0 }}
          animate={{ width: `${progress}%` }}
          transition={{ duration: 1, ease: "easeOut", delay: 0.2 }}
          className="h-full rounded-full"
          style={{
            backgroundColor: color,
          }}
        />
      </div>
    </div>
  );
}