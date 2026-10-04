#pragma once
#include <barrier>
#include <thread>
#include <functional>
#include <mutex>
#include <exception>
class SMPool {
 unsigned sms,threads;std::barrier<> start,finish;std::vector<std::thread> workers;std::function<void(unsigned)> job;bool stop=false;std::exception_ptr error;std::mutex lock;
public:
 SMPool(unsigned ns,unsigned n):sms(ns),threads(std::min(ns,n)),start(threads+1),finish(threads+1){for(unsigned w=0;w<threads;w++)workers.emplace_back([&,w]{for(;;){start.arrive_and_wait();if(stop)break;try{for(unsigned s=w;s<sms;s+=threads)job(s);}catch(...){std::lock_guard<std::mutex>guard(lock);if(!error)error=std::current_exception();}finish.arrive_and_wait();}});}
 ~SMPool(){stop=true;start.arrive_and_wait();for(auto&t:workers)t.join();}
 void run(std::function<void(unsigned)> f){if(!threads){for(unsigned s=0;s<sms;s++)f(s);return;}job=std::move(f);error=nullptr;start.arrive_and_wait();finish.arrive_and_wait();if(error)std::rethrow_exception(error);}
};
