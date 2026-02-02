import { createConsumer, type Consumer } from '@rails/actioncable'

let sharedConsumer: Consumer | null = null

export function getConsumer(url?: string): Consumer {
  if (!sharedConsumer) {
    sharedConsumer = createConsumer(url ?? '/cable')
  }
  return sharedConsumer
}

export function setConsumer(consumer: Consumer): void {
  sharedConsumer = consumer
}
