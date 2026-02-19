import React from 'react';
import { motion } from 'motion/react';
import { Apple } from 'lucide-react';

interface AuthLandingScreenProps {
  onContinueWithApple: () => void;
  onContinueWithGoogle: () => void;
  onContinueAsGuest?: () => void;
}

export function AuthLandingScreen({ 
  onContinueWithApple, 
  onContinueWithGoogle,
  onContinueAsGuest 
}: AuthLandingScreenProps) {
  return (
    <div className="h-screen bg-[#121212] flex flex-col overflow-hidden">
      {/* Content */}
      <div className="flex-1 flex flex-col items-center justify-center px-6 pb-32">
        {/* Logo */}
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.6, type: 'spring', stiffness: 100 }}
          className="mb-8"
        >
          <div className="w-24 h-24 rounded-[24px] bg-gradient-to-br from-[#7B61FF] to-[#A78BFA] flex items-center justify-center shadow-2xl shadow-[#7B61FF]/40 mb-6">
            <span className="text-white text-4xl font-bold">C</span>
          </div>
          <h1 className="text-white text-4xl font-bold text-center mb-3">CMPYS</h1>
          <p className="text-[#A1A1AA] text-center max-w-xs leading-relaxed">
            Compare your success with the world's greatest achievers
          </p>
        </motion.div>

        {/* Feature Pills */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2, duration: 0.5 }}
          className="flex flex-wrap justify-center gap-2 mb-12"
        >
          {['Track Progress', 'Compare Timelines', 'Get Inspired'].map((feature, idx) => (
            <motion.div
              key={feature}
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.3 + idx * 0.1, duration: 0.4 }}
              className="px-4 py-2 bg-[#1C1C1E] border border-[#2A2A2E] rounded-full"
            >
              <span className="text-[#A1A1AA] text-sm">{feature}</span>
            </motion.div>
          ))}
        </motion.div>

        {/* Auth Buttons */}
        <div className="w-full max-w-sm space-y-3">
          {/* Apple Sign In */}
          <motion.button
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.5, duration: 0.5 }}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            onClick={onContinueWithApple}
            className="w-full flex items-center justify-center gap-3 px-6 py-4 bg-white rounded-[16px] shadow-lg"
          >
            <Apple className="w-5 h-5 text-black" fill="currentColor" />
            <span className="text-black font-medium">Continue with Apple</span>
          </motion.button>

          {/* Google Sign In */}
          <motion.button
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.6, duration: 0.5 }}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            onClick={onContinueWithGoogle}
            className="w-full flex items-center justify-center gap-3 px-6 py-4 bg-[#1C1C1E] border-2 border-[#2A2A2E] rounded-[16px]"
          >
            <svg className="w-5 h-5" viewBox="0 0 24 24">
              <path
                fill="#4285F4"
                d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
              />
              <path
                fill="#34A853"
                d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
              />
              <path
                fill="#FBBC05"
                d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
              />
              <path
                fill="#EA4335"
                d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
              />
            </svg>
            <span className="text-white font-medium">Continue with Google</span>
          </motion.button>

          {/* Guest */}
          {onContinueAsGuest && (
            <motion.button
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.7, duration: 0.5 }}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              onClick={onContinueAsGuest}
              className="w-full px-6 py-4 text-[#7B61FF] font-medium"
            >
              Continue as guest
            </motion.button>
          )}
        </div>

        {/* Disclaimer */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.8, duration: 0.5 }}
          className="text-[#A1A1AA] text-xs text-center mt-8 max-w-sm leading-relaxed"
        >
          By continuing, you agree to our{' '}
          <button className="text-[#7B61FF] underline">Terms of Service</button> and{' '}
          <button className="text-[#7B61FF] underline">Privacy Policy</button>
        </motion.p>
      </div>
    </div>
  );
}
