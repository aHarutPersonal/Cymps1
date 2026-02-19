import React from 'react';
import { motion } from 'motion/react';

interface TagChipProps {
  label: string;
  selected?: boolean;
  onClick?: () => void;
  variant?: 'default' | 'category';
  className?: string;
  icon?: React.ReactNode;
}

export function TagChip({ label, selected = false, onClick, variant = 'default', className = '', icon }: TagChipProps) {
  const baseClasses = "px-4 py-2 rounded-full transition-all flex items-center gap-2";
  
  const variantClasses = {
    default: selected 
      ? 'bg-[#7B61FF] text-white' 
      : 'bg-[#1C1C1E] text-[#A1A1AA] border border-[#2A2A2E]',
    category: 'bg-[#7B61FF]/10 text-[#7B61FF] border border-[#7B61FF]/20'
  };

  return (
    <motion.button
      onClick={onClick}
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      animate={selected ? { scale: [1, 1.05, 1] } : {}}
      transition={selected ? { 
        type: "tween",
        duration: 0.3, 
        ease: "easeInOut" 
      } : { 
        type: "spring", 
        stiffness: 300, 
        damping: 20 
      }}
      className={`${baseClasses} ${variantClasses[variant]} ${className}`}
    >
      {icon}
      {label}
    </motion.button>
  );
}