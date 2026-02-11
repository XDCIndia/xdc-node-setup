'use client';

import { useEffect, useState, useRef } from 'react';

export function useCountUp(end: number, duration = 1000, start = 0) {
  const [value, setValue] = useState(start);
  const startTimeRef = useRef<number | null>(null);
  const startValueRef = useRef(start);
  
  useEffect(() => {
    if (end === start) return;
    
    startValueRef.current = value;
    startTimeRef.current = null;
    
    const animate = (currentTime: number) => {
      if (startTimeRef.current === null) {
        startTimeRef.current = currentTime;
      }
      
      const elapsed = currentTime - startTimeRef.current;
      const progress = Math.min(1, elapsed / duration);
      
      // Ease out cubic
      const easeOut = 1 - Math.pow(1 - progress, 3);
      
      const currentValue = Math.floor(startValueRef.current + (end - startValueRef.current) * easeOut);
      setValue(currentValue);
      
      if (progress < 1) {
        requestAnimationFrame(animate);
      }
    };
    
    const animationId = requestAnimationFrame(animate);
    return () => cancelAnimationFrame(animationId);
  }, [end, duration]);
  
  return value;
}

export function useAnimatedNumber(value: number, duration = 1000) {
  const [displayValue, setDisplayValue] = useState(value);
  const previousValueRef = useRef(value);
  
  useEffect(() => {
    const start = previousValueRef.current;
    const end = value;
    const diff = end - start;
    
    if (diff === 0) return;
    
    let startTime: number | null = null;
    
    const animate = (currentTime: number) => {
      if (startTime === null) startTime = currentTime;
      const elapsed = currentTime - startTime;
      const progress = Math.min(1, elapsed / duration);
      const easeOut = 1 - Math.pow(1 - progress, 3);
      
      setDisplayValue(Math.floor(start + diff * easeOut));
      
      if (progress < 1) {
        requestAnimationFrame(animate);
      } else {
        previousValueRef.current = end;
      }
    };
    
    requestAnimationFrame(animate);
  }, [value, duration]);
  
  return displayValue;
}
