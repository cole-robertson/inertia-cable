import { createContext, useContext, useMemo } from 'react'
import { createConsumer, type Consumer } from '@rails/actioncable'

const InertiaCableContext = createContext<Consumer | null>(null)

export interface InertiaCableProviderProps {
  url?: string
  children: React.ReactNode
}

export function InertiaCableProvider({ url, children }: InertiaCableProviderProps) {
  const consumer = useMemo(() => createConsumer(url ?? '/cable'), [url])

  return (
    <InertiaCableContext.Provider value={consumer}>
      {children}
    </InertiaCableContext.Provider>
  )
}

export function useInertiaCableConsumer(): Consumer | null {
  return useContext(InertiaCableContext)
}
