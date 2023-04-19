#pragma once
// A thread safe queue.
template <class T>
	class SafeQueue {
	private:
		std::queue<T>			q;	// this creates a container<T>
		mutable std::mutex		m;
		std::condition_variable	c;

	public:
		SafeQueue() : q(){}
		~SafeQueue()=default;

		// Add an element to the queue.
		void enqueue(T t){
			std::lock_guard<std::mutex> lock(m);	// created on stack so it ends on return
			q.push(t);								// put on end of queue
			c.notify_one();							// wake up anybody waiting for us
		}

		// Get the start element.
		// If the queue is empty, wait till an element is available.
		T dequeue(){
			std::unique_lock<std::mutex> lock(m);	// on the stack so it clears as we return
			while(q.empty())						// release lock as long as the wait and reacquire it afterwards.
				c.wait(lock);						// this could be wait_for or wait_until if we wanted time-outs
			T val = q.front();						// get the next queue item
			q.pop();								// remove next queue entry from queue
			return val;
		}
		// test if we will block
		bool empty() const {
			return q.empty();						// queue.empty is const
		}
		// count
		int count() const {
			return (int)q.size();						// queue.count is const
		}
	};
