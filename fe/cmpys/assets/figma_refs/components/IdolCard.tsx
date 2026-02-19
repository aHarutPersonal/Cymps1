import React from 'react';
import { motion } from 'motion/react';
import { TagChip } from './TagChip';

interface IdolCardProps {
  name: string;
  domain: string;
  match?: number;
  avatar?: string;
  onClick?: () => void;
}

export function IdolCard({ name, domain, match, avatar, onClick }: IdolCardProps) {
  return (
    <motion.div
      onClick={onClick}
      whileHover={{ scale: 1.02, x: 4 }}
      whileTap={{ scale: 0.98 }}
      transition={{ type: "spring", stiffness: 300, damping: 20 }}
      className="bg-[#1C1C1E] rounded-[20px] p-4 flex items-center gap-4 border border-[#2A2A2E] cursor-pointer"
    >
      <motion.div
        whileHover={{ rotate: [0, -5, 5, 0] }}
        transition={{ type: "tween", duration: 0.5 }}
        className="w-14 h-14 rounded-full bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center overflow-hidden flex-shrink-0"
      >
        {avatar ? (
          <img src={avatar} alt={name} className="w-full h-full object-cover" />
        ) : (
          <span className="text-white">{name.charAt(0)}</span>
        )}
      </motion.div>
      <div className="flex-1 min-w-0">
        <h3 className="text-white truncate">{name}</h3>
        <div className="flex items-center gap-2 mt-1">
          <TagChip label={domain} variant="category" className="text-xs px-3 py-1" />
        </div>
      </div>
      {match !== undefined && (
        <motion.div
          initial={{ opacity: 0, scale: 0 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.2, type: "spring" }}
          className="text-[#7B61FF] flex-shrink-0"
        >
          {match}%
        </motion.div>
      )}
    </motion.div>
  );
}