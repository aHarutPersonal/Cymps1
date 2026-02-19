import React from 'react';
import { motion } from 'motion/react';

interface PrimaryButtonProps {
  children: React.ReactNode;
  onClick?: () => void;
  fullWidth?: boolean;
  className?: string;
  disabled?: boolean;
}

export function PrimaryButton({ children, onClick, fullWidth = true, className = '', disabled = false }: PrimaryButtonProps) {
  return (
    <motion.button
      onClick={disabled ? undefined : onClick}
      whileHover={disabled ? {} : { scale: 1.02 }}
      whileTap={disabled ? {} : { scale: 0.98 }}
      transition={{ type: "spring", stiffness: 400, damping: 17 }}
      disabled={disabled}
      className={`px-6 py-4 rounded-[20px] transition-all ${
        disabled 
          ? 'bg-[#1C1C1E] text-[#A1A1AA] cursor-not-allowed border border-[#2A2A2E]' 
          : 'bg-[#7B61FF] text-white active:scale-95'
      } ${fullWidth ? 'w-full' : ''} ${className}`}
    >
      {children}
    </motion.button>
  );
}